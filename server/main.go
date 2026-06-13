package main

import (
	"context"
	"crypto/tls"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	chiMiddleware "github.com/go-chi/chi/v5/middleware"
	"golang.org/x/crypto/acme/autocert"
	"golang.org/x/time/rate"

	"fridgecheck/anthropic"
	"fridgecheck/auth"
	"fridgecheck/config"
	"fridgecheck/db"
	"fridgecheck/handlers"
	"fridgecheck/middleware"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(log)

	cfg, err := config.Load()
	if err != nil {
		log.Error("config error", "err", err)
		os.Exit(1)
	}

	database, err := db.Open(cfg.DBPath)
	if err != nil {
		log.Error("db open failed", "err", err)
		os.Exit(1)
	}
	defer database.Close()

	anth := anthropic.NewClient(cfg.AnthropicAPIKey)
	appleVerifier := auth.NewAppleVerifier(cfg.AppleBundleID)

	rootCtx, rootCancel := context.WithCancel(context.Background())
	defer rootCancel()

	r := chi.NewRouter()

	// Global middleware
	// Trust X-Forwarded-For only when a proxy we control sets it; otherwise
	// clients could spoof the header to dodge the per-IP rate limits.
	if cfg.BehindProxy {
		r.Use(chiMiddleware.RealIP)
	}
	r.Use(chiMiddleware.RequestID)
	r.Use(chiMiddleware.Logger)
	r.Use(chiMiddleware.Recoverer)
	r.Use(middleware.CORS)
	r.Use(middleware.SecurityHeaders)
	r.Use(middleware.RateLimit(rootCtx, rate.Limit(10), 30))

	// Health
	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok"}`))
	})

	// Public: tiny body limit
	authHandler := handlers.NewAuthHandler(database, appleVerifier, cfg.JWTSecret)
	r.Group(func(r chi.Router) {
		r.Use(middleware.MaxBodySize(8 * 1024))
		r.With(middleware.RateLimit(rootCtx, rate.Limit(5.0/60.0), 5)).
			Post("/v1/auth/apple", authHandler.Apple)
	})

	// Authenticated
	meHandler := handlers.NewMeHandler(database, cfg.ScanLimit, cfg.RecipesLimit)
	scanHandler := handlers.NewScanHandler(database, anth, cfg.ScanModel(), cfg.ScanLimit)
	recipesHandler := handlers.NewRecipesHandler(database, anth, cfg.RecipesModel(), cfg.RecipesLimit)

	r.Group(func(r chi.Router) {
		r.Use(middleware.Auth(cfg.JWTSecret))

		r.With(middleware.MaxBodySize(8 * 1024)).Get("/v1/me", meHandler.Get)
		r.With(middleware.MaxBodySize(8 * 1024)).Delete("/v1/me", meHandler.Delete)

		// Scan: up to 15 images × ~0.5 MB base64 each (1024px q0.6) + slack = 16 MB cap
		r.With(middleware.MaxBodySize(16 * 1024 * 1024)).Post("/v1/scan", scanHandler.Post)
		// Recipes: JSON only, 64 KB is plenty
		r.With(middleware.MaxBodySize(64 * 1024)).Post("/v1/recipes", recipesHandler.Post)
	})

	srv := buildServer(cfg, r, log)

	done := make(chan os.Signal, 1)
	signal.Notify(done, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		log.Info("server starting", "env", cfg.Env, "addr", srv.Addr, "behind_proxy", cfg.BehindProxy)
		var err error
		if cfg.Env == "prod" && !cfg.BehindProxy {
			err = srv.ListenAndServeTLS("", "")
		} else {
			err = srv.ListenAndServe()
		}
		if err != nil && err != http.ErrServerClosed {
			log.Error("server error", "err", err)
			os.Exit(1)
		}
	}()

	<-done
	log.Info("shutting down...")
	rootCancel()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
}

func buildServer(cfg *config.Config, handler http.Handler, log *slog.Logger) *http.Server {
	if cfg.Env == "prod" && !cfg.BehindProxy {
		m := &autocert.Manager{
			Cache:      autocert.DirCache(cfg.CertDir),
			Prompt:     autocert.AcceptTOS,
			HostPolicy: autocert.HostWhitelist(config.Domain),
		}
		go func() {
			httpSrv := &http.Server{
				Addr:         ":80",
				Handler:      m.HTTPHandler(http.HandlerFunc(redirectHTTPS)),
				ReadTimeout:  5 * time.Second,
				WriteTimeout: 5 * time.Second,
			}
			log.Info("http redirect server starting", "addr", ":80")
			if err := httpSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				log.Error("http redirect error", "err", err)
			}
		}()
		tlsCfg := m.TLSConfig()
		tlsCfg.MinVersion = tls.VersionTLS12
		return &http.Server{
			Addr:         ":443",
			Handler:      handler,
			TLSConfig:    tlsCfg,
			ReadTimeout:  60 * time.Second,
			WriteTimeout: 5 * time.Minute,
			IdleTimeout:  60 * time.Second,
		}
	}
	return &http.Server{
		Addr:         cfg.Addr,
		Handler:      handler,
		ReadTimeout:  60 * time.Second,
		WriteTimeout: 5 * time.Minute,
		IdleTimeout:  60 * time.Second,
	}
}

func redirectHTTPS(w http.ResponseWriter, r *http.Request) {
	target := "https://" + config.Domain + r.URL.RequestURI()
	http.Redirect(w, r, target, http.StatusMovedPermanently)
}
