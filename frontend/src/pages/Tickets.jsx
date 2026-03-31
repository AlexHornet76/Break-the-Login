import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { createTicket, listTickets, getTicketById, updateTicketById } from '../api/tickets'

export default function Tickets() {
  const navigate = useNavigate()

  const [tickets, setTickets] = useState([])
  const [error, setError] = useState('')
  const [info, setInfo] = useState('')

  // create form
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [severity, setSeverity] = useState('LOW')

  // get/update by id (idor demo)
  const [ticketId, setTicketId] = useState('')
  const [oneTicket, setOneTicket] = useState(null)

  const [editTitle, setEditTitle] = useState('')
  const [editDescription, setEditDescription] = useState('')
  const [editSeverity, setEditSeverity] = useState('LOW')
  const [editStatus, setEditStatus] = useState('OPEN')

  async function refresh() {
    setError('')
    setInfo('')
    try {
      const res = await listTickets()
      setTickets(res.data)
    } catch (e) {
      setError(e?.response?.data?.error || e?.response?.data || 'Eroare la list tickets')
    }
  }

  useEffect(() => {
    refresh()
  }, [])

  async function onCreate(e) {
    e.preventDefault()
    setError('')
    setInfo('')
    try {
      await createTicket(title, description, severity)
      setTitle('')
      setDescription('')
      setSeverity('LOW')
      setInfo('Ticket creat.')
      await refresh()
    } catch (e2) {
      setError(e2?.response?.data?.error || e2?.response?.data || 'Eroare la create ticket')
    }
  }

  async function loadTicketById(id) {
    setError('')
    setInfo('')
    setOneTicket(null)

    if (!id) {
      setError('Introdu un Ticket ID.')
      return
    }

    try {
      const res = await getTicketById(id)
      setOneTicket(res.data)

      // prefill edit fields
      setEditTitle(res.data.title || '')
      setEditDescription(res.data.description || '')
      setEditSeverity(res.data.severity || 'LOW')
      setEditStatus(res.data.status || 'OPEN')

      setInfo(`Ticket #${id} încărcat.`)
    } catch (e2) {
      setError(e2?.response?.data?.error || e2?.response?.data || 'Eroare la get ticket by id')
    }
  }

  async function onGetById(e) {
    e.preventDefault()
    await loadTicketById(ticketId)
  }

  async function onUpdateById(e) {
  e.preventDefault()
  setError('')
  setInfo('')

  if (!ticketId) {
    setError('Introdu un Ticket ID.')
    return
  }

  try {
    await updateTicketById(ticketId, editTitle, editDescription, editSeverity, editStatus)

    // refresh tabelul
    await refresh()

    // inchide panoul de edit si revino doar la tabel
    setOneTicket(null)
    setTicketId('')
    setInfo('Ticket modificat.')
  } catch (e2) {
    setError(e2?.response?.data?.error || e2?.response?.data || 'Eroare la update ticket')
  }
}

  function goDashboard() {
    navigate('/dashboard')
  }

  // UI helpers
  function TableCell({ children }) {
    return (
      <td style={{ padding: '10px 10px', borderTop: '1px solid #eee', fontSize: 13, verticalAlign: 'top' }}>
        {children}
      </td>
    )
  }

  return (
    <div className="page-center">
      <div className="card" style={{ maxWidth: 900 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
          <h2 style={{ marginBottom: 0 }}>Tickets</h2>

          <button
            onClick={goDashboard}
            style={{ background: 'none', border: '1px solid #ddd', borderRadius: 6, padding: '6px 14px', cursor: 'pointer', fontSize: 13 }}
          >
            Înapoi la Dashboard
          </button>
        </div>

        {info && <div className="success">{info}</div>}
        {error && <div className="error">{error}</div>}

        {/* CREATE */}
        <div style={{ marginTop: 14 }}>
          <h3 style={{ marginBottom: 8 }}>Creează ticket</h3>

          <form onSubmit={onCreate}>
            <div className="field">
              <label>Title</label>
              <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Ex: Acces la VPN" />
            </div>

            <div className="field">
              <label>Description</label>
              <input value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Detalii interne..." />
            </div>

            <div className="field">
              <label>Severity</label>
              <select value={severity} onChange={(e) => setSeverity(e.target.value)}>
                <option value="LOW">LOW</option>
                <option value="MED">MED</option>
                <option value="HIGH">HIGH</option>
              </select>
            </div>

            <button className="btn" type="submit">
              Creează
            </button>
          </form>
        </div>

        <hr style={{ margin: '18px 0', border: 'none', borderTop: '1px solid #eee' }} />

        {/* GET + UPDATE BY ID */}
        <div>
          <h3 style={{ marginBottom: 8 }}>Caută / Modifică după ID</h3>

          <form onSubmit={onGetById} style={{ display: 'flex', gap: 8, alignItems: 'end', flexWrap: 'wrap' }}>
            <div className="field" style={{ marginBottom: 0, minWidth: 180 }}>
              <label>Ticket ID</label>
              <input value={ticketId} onChange={(e) => setTicketId(e.target.value)} placeholder="Ex: 1" />
            </div>

            <button className="btn" type="submit" style={{ width: 'auto', padding: '10px 14px' }}>
              Încarcă
            </button>

            <button
              type="button"
              onClick={() => { setOneTicket(null); setInfo(''); setError('') }}
              style={{ background: 'none', border: '1px solid #ddd', borderRadius: 8, padding: '10px 14px', cursor: 'pointer' }}
            >
              Clear
            </button>
          </form>

          {oneTicket && (
            <div style={{ marginTop: 12, background: '#f8fafc', borderRadius: 10, padding: 12 }}>
              <p style={{ fontSize: 13, color: '#666', marginBottom: 8 }}>Ticket încărcat:</p>

              <div style={{ display: 'grid', gridTemplateColumns: '140px 1fr', gap: 8, fontSize: 13 }}>
                <div><strong>ID</strong></div><div>{oneTicket.id}</div>
                <div><strong>Owner</strong></div><div>{oneTicket.owner_id}</div>
                <div><strong>Title</strong></div><div>{oneTicket.title}</div>
                <div><strong>Description</strong></div><div>{oneTicket.description}</div>
                <div><strong>Severity</strong></div><div>{oneTicket.severity}</div>
                <div><strong>Status</strong></div><div>{oneTicket.status}</div>
              </div>

              <div style={{ marginTop: 14 }}>
                <h4 style={{ marginBottom: 8 }}>Edit (PUT)</h4>
                <form onSubmit={onUpdateById}>
                  <div className="field">
                    <label>Title</label>
                    <input value={editTitle} onChange={(e) => setEditTitle(e.target.value)} />
                  </div>

                  <div className="field">
                    <label>Description</label>
                    <input value={editDescription} onChange={(e) => setEditDescription(e.target.value)} />
                  </div>

                  <div className="field">
                    <label>Severity</label>
                    <select value={editSeverity} onChange={(e) => setEditSeverity(e.target.value)}>
                      <option value="LOW">LOW</option>
                      <option value="MED">MED</option>
                      <option value="HIGH">HIGH</option>
                    </select>
                  </div>

                  <div className="field">
                    <label>Status</label>
                    <select value={editStatus} onChange={(e) => setEditStatus(e.target.value)}>
                      <option value="OPEN">OPEN</option>
                      <option value="IN_PROGRESS">IN_PROGRESS</option>
                      <option value="RESOLVED">RESOLVED</option>
                    </select>
                  </div>

                  <button className="btn" type="submit">
                    Salvează modificările
                  </button>
                </form>
              </div>
            </div>
          )}
        </div>

        <hr style={{ margin: '18px 0', border: 'none', borderTop: '1px solid #eee' }} />

        {/* LIST TABLE */}
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
            <h3 style={{ marginBottom: 0 }}>Toate ticket-urile</h3>
            <button
              onClick={refresh}
              style={{ background: 'none', border: '1px solid #ddd', borderRadius: 8, padding: '8px 12px', cursor: 'pointer', fontSize: 13 }}
            >
              Refresh
            </button>
          </div>

          <div style={{ overflowX: 'auto', border: '1px solid #eee', borderRadius: 10 }}>
            <table style={{ width: '100%', borderCollapse: 'collapse' }}>
              <thead style={{ background: '#f8fafc' }}>
                <tr>
                  <th style={{ textAlign: 'left', padding: '10px 10px', fontSize: 12, color: '#555' }}>ID</th>
                  <th style={{ textAlign: 'left', padding: '10px 10px', fontSize: 12, color: '#555' }}>Title</th>
                  <th style={{ textAlign: 'left', padding: '10px 10px', fontSize: 12, color: '#555' }}>Severity</th>
                  <th style={{ textAlign: 'left', padding: '10px 10px', fontSize: 12, color: '#555' }}>Status</th>
                  <th style={{ textAlign: 'left', padding: '10px 10px', fontSize: 12, color: '#555' }}>Owner</th>
                  <th style={{ textAlign: 'left', padding: '10px 10px', fontSize: 12, color: '#555' }}>Actions</th>
                </tr>
              </thead>

              <tbody>
                {tickets.length === 0 ? (
                  <tr>
                    <td colSpan={6} style={{ padding: 12, fontSize: 13, color: '#666' }}>
                      Nu există tickete încă.
                    </td>
                  </tr>
                ) : (
                  tickets.map((t) => (
                    <tr key={t.id}>
                      <TableCell>{t.id}</TableCell>
                      <TableCell>
                        <div style={{ fontWeight: 600 }}>{t.title}</div>
                        {t.description ? (
                          <div style={{ fontSize: 12, color: '#666', marginTop: 2 }}>
                            {t.description}
                          </div>
                        ) : null}
                      </TableCell>
                      <TableCell>{t.severity}</TableCell>
                      <TableCell>{t.status}</TableCell>
                      <TableCell>{t.owner_id}</TableCell>
                      <TableCell>
                        <button
                          type="button"
                          onClick={() => { setTicketId(String(t.id)); loadTicketById(String(t.id)) }}
                          style={{ background: 'none', border: '1px solid #ddd', borderRadius: 8, padding: '6px 10px', cursor: 'pointer', fontSize: 12 }}
                        >
                          View
                        </button>
                      </TableCell>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>

      </div>
    </div>
  )
}