package handlers

import (
	"database/sql"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"Break-the-Login/backend/db"

	"github.com/golang-jwt/jwt/v5"
)

// getTokenFromRequest - token from cookie or Authorization header
func getTokenFromRequest(r *http.Request) string {
	if cookie, err := r.Cookie("auth_token"); err == nil {
		return cookie.Value
	}
	auth := r.Header.Get("Authorization")
	if strings.HasPrefix(auth, "Bearer ") && len(auth) > 7 {
		return strings.TrimSpace(auth[7:])
	}
	return ""
}

// parseIntClaim - jwt MapClaims can be float64/string
func parseIntClaim(v any) (int, error) {
	switch t := v.(type) {
	case float64:
		return int(t), nil
	case int:
		return t, nil
	case string:
		n, err := strconv.Atoi(t)
		if err != nil {
			return 0, err
		}
		return n, nil
	default:
		return 0, errors.New("bad claim type")
	}
}

func getUserIDFromRequest(r *http.Request) (int, error) {
	tokenStr := getTokenFromRequest(r)
	if tokenStr == "" {
		return 0, errors.New("unauthenticated")
	}

	// Validate signature + exp/nbf/iat (MapClaims supports RegisteredClaims validation)
	token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
		return jwtSecret, nil
	}, jwt.WithValidMethods([]string{"HS256"}))
	if err != nil || !token.Valid {
		return 0, errors.New("invalid token")
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return 0, errors.New("invalid claims")
	}

	// basic issuer check
	if iss, _ := claims["iss"].(string); iss == "" || iss != "break-the-login" {
		return 0, errors.New("invalid issuer")
	}

	uid, err := parseIntClaim(claims["user_id"])
	if err != nil || uid <= 0 {
		return 0, errors.New("missing user_id")
	}

	tv, err := parseIntClaim(claims["tv"])
	if err != nil {
		return 0, errors.New("missing token version")
	}

	// compare tv with DB token_version (logout/reset revocation)
	var currentTV int
	err = db.DB.QueryRow("SELECT token_version FROM users WHERE id = ?", uid).Scan(&currentTV)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return 0, errors.New("user not found")
		}
		return 0, errors.New("db error")
	}
	if tv != currentTV {
		return 0, errors.New("revoked token")
	}

	return uid, nil
}
