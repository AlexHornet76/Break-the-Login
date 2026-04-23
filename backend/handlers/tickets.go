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

	//fara validare pe severity/status (accepta orice)
	if req.Severity == "" {
		req.Severity = "LOW"
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

	// audit log
	db.DB.Exec("INSERT INTO audit_logs (user_id, action, ip_address) VALUES (?, ?, ?)",
		userID, "CREATE_TICKET", r.RemoteAddr)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"message":   "Ticket creat",
		"ticket_id": ticketID,
	})
}

// GET /api/tickets (VULNERABIL: returneaza toate ticket-urile)
func ListTickets(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserIDFromRequest(r)
	if err != nil {
		http.Error(w, `{"error":"Neautentificat"}`, 401)
		return
	}

	rows, err := db.DB.Query("SELECT id, title, description, severity, status, owner_id, created_at, updated_at FROM tickets ORDER BY id DESC")
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

// GET /api/tickets/{id} (VULNERABIL: IDOR - nu verifica owner_id)
func GetTicketByID(w http.ResponseWriter, r *http.Request) {
	userID, err := getUserIDFromRequest(r)
	if err != nil {
		http.Error(w, `{"error":"Neautentificat"}`, 401)
		return
	}

	// extrage id din URL: /api/tickets/{id}
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

	err = db.DB.QueryRow(
		"SELECT id, title, description, severity, status, owner_id, created_at, updated_at FROM tickets WHERE id = ?",
		ticketID,
	).Scan(&id, &title, &description, &severity, &status, &ownerID, &createdAt, &updatedAt)

	if err != nil {
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

// PUT /api/tickets/{id} (VULNERABIL: IDOR - nu verifica owner_id)
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

	var req UpdateTicketRequest
	json.NewDecoder(r.Body).Decode(&req)

	_, err = db.DB.Exec(
		"UPDATE tickets SET title = ?, description = ?, severity = ?, status = ?, updated_at = ? WHERE id = ?",
		req.Title, req.Description, req.Severity, req.Status, time.Now(), ticketID,
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
