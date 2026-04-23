package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"

	"Break-the-Login/backend/db"
)

type CreateTicketRequest struct {
	Title       string `json:"title"`
	Description string `json:"description"`
	Severity    string `json:"severity"`
}

type UpdateTicketRequest struct {
	Title       string `json:"title"`
	Description string `json:"description"`
	Severity    string `json:"severity"`
	Status      string `json:"status"`
}

var validSeverities = map[string]bool{"LOW": true, "MEDIUM": true, "HIGH": true}
var validStatuses = map[string]bool{"OPEN": true, "IN_PROGRESS": true, "CLOSED": true}

// POST /api/tickets
func CreateTicket(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserIDFromRequest(r)
	if err != nil {
		http.Error(w, `{"error":"Neautentificat"}`, 401)
		return
	}

	var req CreateTicketRequest
	json.NewDecoder(r.Body).Decode(&req)

	if req.Title == "" {
		http.Error(w, `{"error":"Title obligatoriu"}`, 400)
		return
	}

	if req.Severity == "" {
		req.Severity = "LOW"
	}

	// validare severity
	if !validSeverities[req.Severity] {
		http.Error(w, `{"error":"Severity invalid. Valori acceptate: LOW, MEDIUM, HIGH"}`, 400)
		return
	}

	res, err := db.DB.Exec(
		"INSERT INTO tickets (title, description, severity, status, owner_id, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
		req.Title, req.Description, req.Severity, "OPEN", userID, time.Now(),
	)
	if err != nil {
		http.Error(w, `{"error":"Eroare DB"}`, 500)
		return
	}

	ticketID, _ := res.LastInsertId()

	db.DB.Exec("INSERT INTO audit_logs (user_id, action, ip_address) VALUES (?, ?, ?)",
		userID, "CREATE_TICKET", r.RemoteAddr)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"message":   "Ticket creat",
		"ticket_id": ticketID,
	})
}

// GET /api/tickets — returneaza doar ticketele userului autentificat
func ListTickets(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserIDFromRequest(r)
	if err != nil {
		http.Error(w, `{"error":"Neautentificat"}`, 401)
		return
	}

	// FIX IDOR: filtram dupa owner_id
	rows, err := db.DB.Query(
		"SELECT id, title, description, severity, status, owner_id, created_at, updated_at FROM tickets WHERE owner_id = ? ORDER BY id DESC",
		userID,
	)
	if err != nil {
		http.Error(w, `{"error":"Eroare DB"}`, 500)
		return
	}
	defer rows.Close()

	type Ticket struct {
		ID          int    `json:"id"`
		Title       string `json:"title"`
		Description string `json:"description"`
		Severity    string `json:"severity"`
		Status      string `json:"status"`
		OwnerID     int    `json:"owner_id"`
		CreatedAt   string `json:"created_at"`
		UpdatedAt   string `json:"updated_at"`
	}

	out := []Ticket{}
	for rows.Next() {
		var t Ticket
		if err := rows.Scan(&t.ID, &t.Title, &t.Description, &t.Severity, &t.Status, &t.OwnerID, &t.CreatedAt, &t.UpdatedAt); err == nil {
			out = append(out, t)
		}
	}

	db.DB.Exec("INSERT INTO audit_logs (user_id, action, ip_address) VALUES (?, ?, ?)",
		userID, "LIST_TICKETS", r.RemoteAddr)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(out)
}

// GET /api/tickets/{id}
func GetTicketByID(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserIDFromRequest(r)
	if err != nil {
		http.Error(w, `{"error":"Neautentificat"}`, 401)
		return
	}

	idStr := strings.TrimPrefix(r.URL.Path, "/api/tickets/")
	ticketID, err := strconv.Atoi(idStr)
	if err != nil {
		http.Error(w, `{"error":"ID invalid"}`, 400)
		return
	}

	var (
		id          int
		title       string
		description string
		severity    string
		status      string
		ownerID     int
		createdAt   string
		updatedAt   string
	)

	// FIX IDOR: WHERE id = ? AND owner_id = ?
	err = db.DB.QueryRow(
		"SELECT id, title, description, severity, status, owner_id, created_at, updated_at FROM tickets WHERE id = ? AND owner_id = ?",
		ticketID, userID,
	).Scan(&id, &title, &description, &severity, &status, &ownerID, &createdAt, &updatedAt)

	if err != nil {
		// returnam 404 intentionat — nu confirmam existenta ticketului
		http.Error(w, `{"error":"Ticket inexistent"}`, 404)
		return
	}

	db.DB.Exec("INSERT INTO audit_logs (user_id, action, resource, resource_id, ip_address) VALUES (?, ?, ?, ?, ?)",
		userID, "VIEW_TICKET", "ticket", strconv.Itoa(ticketID), r.RemoteAddr)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"id":          id,
		"title":       title,
		"description": description,
		"severity":    severity,
		"status":      status,
		"owner_id":    ownerID,
		"created_at":  createdAt,
		"updated_at":  updatedAt,
	})
}

// PUT /api/tickets/{id}
func UpdateTicketByID(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserIDFromRequest(r)
	if err != nil {
		http.Error(w, `{"error":"Neautentificat"}`, 401)
		return
	}

	idStr := strings.TrimPrefix(r.URL.Path, "/api/tickets/")
	ticketID, err := strconv.Atoi(idStr)
	if err != nil {
		http.Error(w, `{"error":"ID invalid"}`, 400)
		return
	}

	// FIX IDOR: verificam ownership inainte de orice modificare
	var ownerID int
	err = db.DB.QueryRow("SELECT owner_id FROM tickets WHERE id = ?", ticketID).Scan(&ownerID)
	if err != nil || ownerID != userID {
		// 404 intentionat — nu confirmam existenta ticketului
		http.Error(w, `{"error":"Ticket inexistent"}`, 404)
		return
	}

	var req UpdateTicketRequest
	json.NewDecoder(r.Body).Decode(&req)

	// validare severity
	if req.Severity != "" && !validSeverities[req.Severity] {
		http.Error(w, `{"error":"Severity invalid. Valori acceptate: LOW, MEDIUM, HIGH"}`, 400)
		return
	}

	// validare status
	if req.Status != "" && !validStatuses[req.Status] {
		http.Error(w, `{"error":"Status invalid. Valori acceptate: OPEN, IN_PROGRESS, CLOSED"}`, 400)
		return
	}

	// FIX IDOR: WHERE id = ? AND owner_id = ? — dubla protectie
	_, err = db.DB.Exec(
		"UPDATE tickets SET title = ?, description = ?, severity = ?, status = ?, updated_at = ? WHERE id = ? AND owner_id = ?",
		req.Title, req.Description, req.Severity, req.Status, time.Now(), ticketID, userID,
	)
	if err != nil {
		http.Error(w, `{"error":"Eroare DB"}`, 500)
		return
	}

	db.DB.Exec("INSERT INTO audit_logs (user_id, action, resource, resource_id, ip_address) VALUES (?, ?, ?, ?, ?)",
		userID, "EDIT_TICKET", "ticket", strconv.Itoa(ticketID), r.RemoteAddr)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"message":   "Ticket modificat",
		"ticket_id": ticketID,
	})
}
