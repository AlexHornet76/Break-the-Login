import axios from 'axios'

const API = axios.create({
  baseURL: 'http://localhost:8080/api',
  withCredentials: true,
})

export const createTicket = (title, description, severity) =>
  API.post('/tickets', { title, description, severity })

export const listTickets = () =>
  API.get('/tickets')

// idor demo: get by id
export const getTicketById = (id) =>
  API.get(`/tickets/${id}`)

// idor demo: update by id
export const updateTicketById = (id, title, description, severity, status) =>
  API.put(`/tickets/${id}`, { title, description, severity, status })