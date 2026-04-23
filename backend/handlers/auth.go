package handlers

import (
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"time"

	"Break-the-Login/backend/db"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

// jwtSecret - lab secret; in real apps use env + rotation
var jwtSecret = []byte("secretdiscret456")

const (
	jwtIssuer    = "break-the-login"
	jwtTTL       = 30 * time.Minute
	resetTTL     = 15 * time.Minute
	lockAfter    = 10
	lockDuration = 15 * time.Minute
)

// Cheie cookie: auth_token
func cookieSecure(r *http.Request) bool {
	// dev flag, helps local testing on http
	if strings.ToLower(os.Getenv("ALLOW_INSECURE_COOKIES")) == "true" {
		return false
	}
	if r.TLS != nil {
		return true
	}
	if strings.ToLower(r.Header.Get("X-Forwarded-Proto")) == "https" {
		return true
	}
	return false
}

func setAuthCookie(w http.ResponseWriter, r *http.Request, token string) {
	http.SetCookie(w, &http.Cookie{
		Name:     "auth_token",
		Value:    token,
		Path:     "/",
		HttpOnly: true,                    // 4.5: blocks JS access
		Secure:   cookieSecure(r),         // 4.5: https only (optional in dev)
		SameSite: http.SameSiteStrictMode, // 4.5: reduce CSRF
		MaxAge:   int(jwtTTL.Seconds()),   // align with exp
	})
}

func clearAuthCookie(w http.ResponseWriter, r *http.Request) {
	http.SetCookie(w, &http.Cookie{
		Name:     "auth_token",
		Value:    "",
		Path:     "/",
		HttpOnly: true,
		Secure:   cookieSecure(r),
		SameSite: http.SameSiteStrictMode,
		Expires:  time.Unix(0, 0),
		MaxAge:   -1,
	})
}

func normalizeEmail(s string) string {
	return strings.TrimSpace(strings.ToLower(s))
}

func invalidCreds(w http.ResponseWriter) {
	http.Error(w, `{"error":"Invalid credentials"}`, http.StatusUnauthorized)
}

type RegisterRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type ForgotPasswordRequest struct {
	Email string `json:"email"`
}

type ResetPasswordRequest struct {
	Token    string `json:"token"`
	Password string `json:"password"`
}

// Register - fixed: password policy + bcrypt
func Register(w http.ResponseWriter, r *http.Request) {
	var req RegisterRequest
	_ = json.NewDecoder(r.Body).Decode(&req)

	req.Email = normalizeEmail(req.Email)

	// 4.1: policy check + generic response
	if req.Email == "" || req.Password == "" || !validatePassword(req.Password) {
		http.Error(w, `{"error":"Invalid input"}`, http.StatusBadRequest)
		return
	}

	// 4.2: store bcrypt hash
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		http.Error(w, `{"error":"Server error"}`, http.StatusInternalServerError)
		return
	}

	_, err = db.DB.Exec(
		"INSERT INTO users (email, password, token_version) VALUES (?, ?, 0)",
		req.Email, string(hash),
	)
	if err != nil {
		// 4.4: no enumeration
		http.Error(w, `{"error":"Invalid input"}`, http.StatusConflict)
		return
	}

	_, _ = db.DB.Exec("INSERT INTO audit_logs (action, ip_address) VALUES (?, ?)",
		"REGISTER", r.RemoteAddr)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"message": "Cont creat cu succes"})
}

// Login - fixed: exp token + cookie flags + token_version claim
func Login(w http.ResponseWriter, r *http.Request) {
	var req LoginRequest
	_ = json.NewDecoder(r.Body).Decode(&req)

	req.Email = normalizeEmail(req.Email)

	if req.Email == "" || req.Password == "" {
		invalidCreds(w)
		return
	}

	var (
		userID       int
		passwordHash string
		failedLogins int
		lockedUntil  sql.NullString
		tokenVersion int
	)

	err := db.DB.QueryRow(
		"SELECT id, password, failed_logins, locked_until, token_version FROM users WHERE email = ?",
		req.Email,
	).Scan(&userID, &passwordHash, &failedLogins, &lockedUntil, &tokenVersion)

	if err != nil {
		// small timing hardening
		_ = bcrypt.CompareHashAndPassword([]byte("$2a$10$7EqJtq98hPqEX7fNZaFWoOhi5J0z7QqZ3G4p1Q1Y7bqfQwQGqK2eW"), []byte(req.Password))
		invalidCreds(w)
		return
	}

	// 4.3 + 4.4: lockout but generic message
	if lockedUntil.Valid && lockedUntil.String != "" {
		if t, err := time.Parse(time.RFC3339, lockedUntil.String); err == nil {
			if time.Now().UTC().Before(t) {
				_, _ = db.DB.Exec(
					"INSERT INTO audit_logs (user_id, action, ip_address) VALUES (?, ?, ?)",
					userID, "LOGIN_BLOCKED_LOCKED", r.RemoteAddr,
				)
				invalidCreds(w)
				return
			}
		}
	}

	// 4.2: bcrypt compare
	if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)); err != nil {
		// 4.3: increment + lock
		lockUntil := time.Now().UTC().Add(lockDuration).Format(time.RFC3339)
		_, _ = db.DB.Exec(`
			UPDATE users
			SET
				failed_logins = failed_logins + 1,
				locked_until = CASE
					WHEN failed_logins + 1 >= ?
					THEN ?
					ELSE locked_until
				END
			WHERE id = ?
		`, lockAfter, lockUntil, userID)

		_, _ = db.DB.Exec(
			"INSERT INTO audit_logs (user_id, action, ip_address) VALUES (?, ?, ?)",
			userID, "LOGIN_FAIL", r.RemoteAddr,
		)

		invalidCreds(w)
		return
	}

	// success: reset counters
	_, _ = db.DB.Exec("UPDATE users SET failed_logins = 0, locked_until = NULL WHERE id = ?", userID)

	// 4.5: exp + token version for revocation
	now := time.Now().UTC()
	exp := now.Add(jwtTTL)

	claims := jwt.MapClaims{
		"iss":     jwtIssuer,
		"user_id": userID,
		"email":   req.Email,

		"iat": now.Unix(),
		"nbf": now.Unix(),
		"exp": exp.Unix(),

		"tv": tokenVersion,
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString(jwtSecret)
	if err != nil {
		http.Error(w, `{"error":"Server error"}`, http.StatusInternalServerError)
		return
	}

	// 4.5: cookie flags
	setAuthCookie(w, r, tokenString)

	_, _ = db.DB.Exec("INSERT INTO audit_logs (user_id, action, ip_address) VALUES (?, ?, ?)",
		userID, "LOGIN_SUCCESS", r.RemoteAddr)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"message": "Autentificare reusita"})
}

// Logout - fixed: revoke tokens server-side
func Logout(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserIDFromRequest(r)
	if err == nil && userID > 0 {
		// 4.5: bump version => old tokens invalid
		_, _ = db.DB.Exec("UPDATE users SET token_version = token_version + 1 WHERE id = ?", userID)

		_, _ = db.DB.Exec("INSERT INTO audit_logs (user_id, action, ip_address) VALUES (?, ?, ?)",
			userID, "LOGOUT", r.RemoteAddr)
	}

	clearAuthCookie(w, r)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"message": "Deconectat"})
}

// Me - fixed: token validated in middleware helper
func Me(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserIDFromRequest(r)
	if err != nil {
		http.Error(w, `{"error":"Neautentificat"}`, http.StatusUnauthorized)
		return
	}

	var email string
	err = db.DB.QueryRow("SELECT email FROM users WHERE id = ?", userID).Scan(&email)
	if err != nil {
		http.Error(w, `{"error":"User invalid"}`, http.StatusUnauthorized)
		return
	}

	_, _ = db.DB.Exec("INSERT INTO audit_logs (user_id, action, ip_address) VALUES (?, ?, ?)",
		userID, "ME", r.RemoteAddr)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"user_id": userID,
		"email":   email,
	})
}

// ForgotPassword - fixed: generic response + random token + expiry
func ForgotPassword(w http.ResponseWriter, r *http.Request) {
	var body ForgotPasswordRequest
	_ = json.NewDecoder(r.Body).Decode(&body)

	email := normalizeEmail(body.Email)

	// 4.4: generic response always
	resp := map[string]string{
		"message": "Daca adresa exista, vei primi instructiuni pentru resetare",
	}

	var userID int
	err := db.DB.QueryRow("SELECT id FROM users WHERE email = ?", email).Scan(&userID)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(resp)
		return
	}

	// 4.6: crypto random token (32 bytes)
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		http.Error(w, `{"error":"Server error"}`, http.StatusInternalServerError)
		return
	}

	// token shown in response for lab; normally send by email
	token := base64.RawURLEncoding.EncodeToString(raw)

	// store hash only
	sum := sha256.Sum256([]byte(token))
	tokenHash := hex.EncodeToString(sum[:])

	expiresAt := time.Now().UTC().Add(resetTTL).Format(time.RFC3339)

	_, _ = db.DB.Exec(
		"INSERT INTO reset_tokens (user_id, token_hash, expires_at, used_at) VALUES (?, ?, ?, NULL)",
		userID, tokenHash, expiresAt,
	)

	_, _ = db.DB.Exec("INSERT INTO audit_logs (user_id, action, ip_address) VALUES (?, ?, ?)",
		userID, "RESET_TOKEN_ISSUED", r.RemoteAddr)

	resp["reset_token"] = token

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

// ResetPassword - fixed: one-time + expiry + bcrypt + revoke sessions
func ResetPassword(w http.ResponseWriter, r *http.Request) {
	var body ResetPasswordRequest
	_ = json.NewDecoder(r.Body).Decode(&body)

	if body.Token == "" || body.Password == "" || !validatePassword(body.Password) {
		http.Error(w, `{"error":"Invalid input"}`, http.StatusBadRequest)
		return
	}

	// hash received token
	sum := sha256.Sum256([]byte(body.Token))
	tokenHash := hex.EncodeToString(sum[:])

	var (
		userID    int
		expiresAt string
		usedAt    sql.NullString
	)

	err := db.DB.QueryRow(
		"SELECT user_id, expires_at, used_at FROM reset_tokens WHERE token_hash = ?",
		tokenHash,
	).Scan(&userID, &expiresAt, &usedAt)

	if err != nil {
		http.Error(w, `{"error":"Token invalid"}`, http.StatusBadRequest)
		return
	}

	if usedAt.Valid && usedAt.String != "" {
		http.Error(w, `{"error":"Token invalid"}`, http.StatusBadRequest)
		return
	}

	expT, err := time.Parse(time.RFC3339, expiresAt)
	if err != nil || time.Now().UTC().After(expT) {
		http.Error(w, `{"error":"Token invalid"}`, http.StatusBadRequest)
		return
	}

	// mark token as used (one-time)
	_, _ = db.DB.Exec(
		"UPDATE reset_tokens SET used_at = ? WHERE token_hash = ? AND used_at IS NULL",
		time.Now().UTC().Format(time.RFC3339), tokenHash,
	)

	// 4.2: bcrypt for new password
	hash, err := bcrypt.GenerateFromPassword([]byte(body.Password), bcrypt.DefaultCost)
	if err != nil {
		http.Error(w, `{"error":"Server error"}`, http.StatusInternalServerError)
		return
	}

	// clear lockout + revoke sessions
	_, err = db.DB.Exec(
		"UPDATE users SET password = ?, failed_logins = 0, locked_until = NULL, token_version = token_version + 1 WHERE id = ?",
		string(hash), userID,
	)
	if err != nil {
		http.Error(w, `{"error":"Server error"}`, http.StatusInternalServerError)
		return
	}

	_, _ = db.DB.Exec("INSERT INTO audit_logs (user_id, action, ip_address) VALUES (?, ?, ?)",
		userID, "PASSWORD_RESET", r.RemoteAddr)

	// clear cookie after reset
	clearAuthCookie(w, r)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"message": "Parola resetata"})
}
