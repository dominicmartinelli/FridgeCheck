package middleware

import (
	"context"
	"net/http"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

// RateLimit is a simple per-IP token bucket. Background goroutine prunes
// idle limiters every 5 minutes. Cancel the root context to stop pruning.
func RateLimit(ctx context.Context, r rate.Limit, burst int) func(http.Handler) http.Handler {
	type entry struct {
		limiter *rate.Limiter
		last    time.Time
	}
	var (
		mu       sync.Mutex
		limiters = make(map[string]*entry)
	)

	go func() {
		t := time.NewTicker(5 * time.Minute)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				mu.Lock()
				cutoff := time.Now().Add(-10 * time.Minute)
				for ip, e := range limiters {
					if e.last.Before(cutoff) {
						delete(limiters, ip)
					}
				}
				mu.Unlock()
			}
		}
	}()

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
			ip := req.RemoteAddr
			mu.Lock()
			e, ok := limiters[ip]
			if !ok {
				e = &entry{limiter: rate.NewLimiter(r, burst)}
				limiters[ip] = e
			}
			e.last = time.Now()
			allowed := e.limiter.Allow()
			mu.Unlock()
			if !allowed {
				http.Error(w, `{"error":"rate_limited"}`, http.StatusTooManyRequests)
				return
			}
			next.ServeHTTP(w, req)
		})
	}
}
