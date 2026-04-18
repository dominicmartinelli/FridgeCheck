package config

import (
	"flag"
	"fmt"
	"os"

	"github.com/BurntSushi/toml"
)

const Domain = "fridge.dkm.net"

type Config struct {
	Env         string `toml:"env"`
	Addr        string `toml:"addr"`
	BehindProxy bool   `toml:"behind_proxy"`

	DBPath  string `toml:"db_path"`
	CertDir string `toml:"cert_dir"`

	JWTSecret      string `toml:"jwt_secret"`
	AppleBundleID  string `toml:"apple_bundle_id"`

	AnthropicAPIKey string `toml:"anthropic_api_key"`
	AnthropicModel  string `toml:"anthropic_model"`

	FreeTierScansPerDay   int `toml:"free_tier_scans_per_day"`
	FreeTierRecipesPerDay int `toml:"free_tier_recipes_per_day"`
}

func Load() (*Config, error) {
	cfgPath := flag.String("config", defaultConfigPath(), "Path to config.toml")
	flag.Parse()

	cfg := defaults()
	if _, err := toml.DecodeFile(*cfgPath, cfg); err != nil {
		return nil, fmt.Errorf("reading config %s: %w", *cfgPath, err)
	}
	return cfg, cfg.validate()
}

func defaults() *Config {
	return &Config{
		Env:                   "dev",
		Addr:                  ":8082",
		DBPath:                "./fridgecheck.db",
		CertDir:               "/var/lib/fridgecheck/certs",
		AppleBundleID:         "com.fridgecheck.app",
		AnthropicModel:        "claude-sonnet-4-5-20250929",
		FreeTierScansPerDay:   5,
		FreeTierRecipesPerDay: 20,
	}
}

func defaultConfigPath() string {
	if _, err := os.Stat("/etc/fridgecheck/config.toml"); err == nil {
		return "/etc/fridgecheck/config.toml"
	}
	return "config.toml"
}

func (c *Config) validate() error {
	if c.DBPath == "" {
		return fmt.Errorf("db_path must be set")
	}
	if len(c.JWTSecret) < 32 {
		return fmt.Errorf("jwt_secret must be at least 32 characters (generate with: openssl rand -hex 32)")
	}
	if c.AnthropicAPIKey == "" {
		return fmt.Errorf("anthropic_api_key is required")
	}
	if c.AppleBundleID == "" {
		return fmt.Errorf("apple_bundle_id is required")
	}
	return nil
}
