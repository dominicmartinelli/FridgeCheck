package auth

import (
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const (
	appleIssuer  = "https://appleid.apple.com"
	appleJWKSURL = "https://appleid.apple.com/auth/keys"
	jwksTTL      = 1 * time.Hour
)

type appleJWK struct {
	Kty string `json:"kty"`
	Kid string `json:"kid"`
	Use string `json:"use"`
	Alg string `json:"alg"`
	N   string `json:"n"`
	E   string `json:"e"`
}

type appleJWKS struct {
	Keys []appleJWK `json:"keys"`
}

// AppleVerifier verifies Apple identity tokens against Apple's rotating JWKS.
// Safe for concurrent use; JWKS are cached and refreshed lazily.
type AppleVerifier struct {
	bundleID string

	mu      sync.RWMutex
	keys    map[string]*rsa.PublicKey // keyed by kid
	fetched time.Time
}

func NewAppleVerifier(bundleID string) *AppleVerifier {
	return &AppleVerifier{bundleID: bundleID, keys: make(map[string]*rsa.PublicKey)}
}

// Verify returns the Apple sub (stable user ID) if the token is valid.
func (v *AppleVerifier) Verify(identityToken string) (string, error) {
	parser := jwt.NewParser(jwt.WithIssuer(appleIssuer), jwt.WithAudience(v.bundleID))
	token, err := parser.Parse(identityToken, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		kid, _ := t.Header["kid"].(string)
		if kid == "" {
			return nil, fmt.Errorf("token missing kid")
		}
		return v.keyByID(kid)
	})
	if err != nil {
		return "", err
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || !token.Valid {
		return "", fmt.Errorf("invalid token")
	}
	sub, _ := claims["sub"].(string)
	if sub == "" {
		return "", fmt.Errorf("token missing sub")
	}
	return sub, nil
}

func (v *AppleVerifier) keyByID(kid string) (*rsa.PublicKey, error) {
	v.mu.RLock()
	key, ok := v.keys[kid]
	fresh := time.Since(v.fetched) < jwksTTL
	v.mu.RUnlock()
	if ok && fresh {
		return key, nil
	}
	if err := v.refresh(); err != nil {
		return nil, err
	}
	v.mu.RLock()
	defer v.mu.RUnlock()
	key, ok = v.keys[kid]
	if !ok {
		return nil, fmt.Errorf("no matching apple key for kid %s", kid)
	}
	return key, nil
}

func (v *AppleVerifier) refresh() error {
	v.mu.Lock()
	defer v.mu.Unlock()
	// double-check: another goroutine may have refreshed while we waited
	if time.Since(v.fetched) < jwksTTL && len(v.keys) > 0 {
		return nil
	}
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Get(appleJWKSURL)
	if err != nil {
		return fmt.Errorf("fetch apple jwks: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("apple jwks http %d", resp.StatusCode)
	}
	var jwks appleJWKS
	if err := json.NewDecoder(resp.Body).Decode(&jwks); err != nil {
		return fmt.Errorf("decode apple jwks: %w", err)
	}
	keys := make(map[string]*rsa.PublicKey, len(jwks.Keys))
	for _, k := range jwks.Keys {
		if k.Kty != "RSA" {
			continue
		}
		pub, err := rsaPublicKey(k.N, k.E)
		if err != nil {
			continue
		}
		keys[k.Kid] = pub
	}
	if len(keys) == 0 {
		return fmt.Errorf("apple jwks contained no usable keys")
	}
	v.keys = keys
	v.fetched = time.Now()
	return nil
}

func rsaPublicKey(nB64, eB64 string) (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(nB64)
	if err != nil {
		return nil, err
	}
	eBytes, err := base64.RawURLEncoding.DecodeString(eB64)
	if err != nil {
		return nil, err
	}
	var e int
	for _, b := range eBytes {
		e = e<<8 | int(b)
	}
	return &rsa.PublicKey{
		N: new(big.Int).SetBytes(nBytes),
		E: e,
	}, nil
}
