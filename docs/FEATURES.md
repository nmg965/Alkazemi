# Features, flows and reports

This file describes everything the live portal does. Everything listed here is implemented in `public/app.js`. Each user also has an in-app **Help & guide**, in both languages, plus a guided tour.

## Contents
1. Navigation and general features
2. Modules (screens)
3. The maintenance approval chain
4. Deadlines (SLA) and escalation
5. Other workflows
6. Reports
7. Roles and the permission matrix
8. Notifications and alerts
9. Settings

---

## 1. Navigation and general features

- **Bilingual UI**: the EN/ع button switches the whole interface to Arabic with right-to-left layout. Each user's choice is remembered.
- **Dark and light mode**: available to every user in the profile menu.
- **Mobile first**: on phones there's a bottom bar plus a **More** button. It can be installed as an app with *Add to Home Screen* (PWA). Guards get a simplified app with large buttons.
- **Building switcher** (top bar): focus every screen on one building, or all of them.
- **Global search**: ticket number, unit code, tenant name, plate number or stock item.
- **Bell**: approvals waiting on you, late-job alerts and reminders.
- **Live sync**: changes appear on every open screen in real time (Supabase Realtime). The sync badge shows Live, Saving… or Reconnecting….
- **Animated numbers**: every count, chart and figure counts up when it appears.
- **Saved pop-up**: after every save, and the screen keeps its scroll position.
- **Guided tour** for each role on first sign-in. It can be restarted from the profile menu.
- **Currency**: KWD by default, with three decimals.
- **Audit trail**: every action is logged with who did it and when.

## 2. Modules (screens)

| Module | Key | What it does |
|---|---|---|
| Dashboard | `dashboard` | KPIs per role: open jobs, late jobs, occupancy, rent collected, "Waiting on you" list, charts |
| Late jobs & escalations | `escalations` | Every late ticket and over-time vehicle repair, alert count, next alert time, **Send alert now** |
| Buildings | `buildings` | Portfolio cards with photos. Building drawer tabs: Overview, Floors & units (stacking plan and floor builder), Documents (statutory docs with expiry dates, custom names), Photos (gallery, cover photo, upload), Planned maintenance, Jobs, Team (**Add more users to this property**). Admins edit everything in place. |
| Units & leases | `units` | Every unit: rental or lease, rent (KWD), tenant, lease start/end, status (occupied, vacant, maintenance) |
| Tenants | `tenants` | Contact, civil ID, nationality, deposit, payment frequency, lease registration number, rent history |
| Vacant inspections | `inspections` | Room-by-room inspection with photos, condition, damages and costs, meters and keys. Print or PDF. Damages turn into tickets in one step. |
| Maintenance | `tickets` | Board and list by stage. Ticket drawer with the approval panel, photos/video, history, technician arrivals, materials and costs |
| Report an issue | `report` | Pick a building, tap the apartment on the floor plan (or a common area), category, photos, urgency |
| Guard tools | `guard` | Report, Emergency, Patrol rounds (OK/Issue/N/A checkpoints), Visitors & contractors log, Technician arrival, Vacant unit check |
| Warehouse | `warehouse` | Stock on hand by store, reorder levels, value. Receive goods, Issue to job, stock count, movement history |
| Fleet | `fleet` | Vehicles (plate, driver, odometer, service, Daftar registration and insurance expiry). Repair jobs with an expected-time dial and over-time alerts |
| Rent collection | `rent` | Monthly rent per unit. **Mark paid** issues a receipt number. CSV import. Overdue reminders |
| Alerts & messages | `alerts` | Every email and WhatsApp message with its delivery status (queued, waiting for keys, sent, failed) |
| Reports | `reports` | See §6 |
| Users & permissions | `users` | Add or edit users, role, per-user permission ticks, assigned buildings, trades, password, active flag |
| Settings | `settings` | SLA hours, repeat interval, escalation roles, owner approval limit, channels, organisation name |
| Live wall | `tv` | Full-screen operations-room display that refreshes every 15 s |
| Help & guide | `help` | 20 bilingual help topics and the tour |

## 3. The maintenance approval chain

```
reported ─► (supervisor pre-approval) ─► mgr_approval ─► owner_approval ─► assigned
   ─► in_progress ─► job_done ─► [procurement] ─► closed
Any approval step can ─► rejected (with a reason)
```

1. **Reported**: a guard, or anyone with `createTicket`, reports an issue with photos and urgency. The building supervisor is alerted.
2. **Supervisor pre-approval** (`supApprove`): confirms the category and urgency and enters a cost estimate (KWD). Reports raised by a supervisor or manager skip this step.
3. **Manager approval** (`mgrApprove`): approves and picks the technician. The right trade is suggested.
4. **Owner approval** (`ownerApprove`): final approval. It's skipped when the estimate is below the *owner approval limit* in Settings (0 = the owner approves everything).
5. **Assigned → In progress**: the technician presses *Start work on site*, and the guard confirms the arrival time.
6. **Job done** (`completeJob`): work notes, materials (deducted from the warehouse), labour cost and after photos. There's an optional *Items must be purchased* box.
7. **Review** (`closeJob`): the manager closes the job, or sends it to **Procurement** (`procure`), which approves the purchase, and then the job closes.

Priorities: **P1 Emergency**, **P2 Urgent**, **P3 Normal**, **P4 Planned**. An *Emergency* report alerts everyone straight away.

## 4. Deadlines (SLA) and escalation

- Emergency and Urgent jobs must close within **24 h**. Normal and Planned jobs have **48 h**. These are configurable. The clock starts at the report, so approval time counts.
- When a job is late, an alert goes to the supervisor, managers, owners and admins (the escalation roles are configurable). It goes out by email, WhatsApp and in-app, and **repeats every 4 h** until the job is closed or rejected. The alert says how late the job is and **who it is waiting on**.
- Vehicle repairs that run past their expected hours alert the worker and the operations manager **every 2 h**.
- This runs **on the server** (`run_escalations()` via pg_cron every 5 minutes), so it works even when no one has the app open. Managers can press **Send alert now**, which calls `escalate_now()`.

## 5. Other workflows

**Vacant unit inspection**: New inspection → choose the unit on the floor plan → go room by room (Good/Fair/Damaged, photos, damages with costs) → meters and keys → summary → submit → supervisor or manager review → *Create repair tickets* from the damages → print or PDF.

**Patrol round**: the guard marks each checkpoint. Each *Issue* becomes a maintenance report automatically.

**Visitors**: check-in (name, company, purpose, unit, ID) and check-out. Contractor visits can be linked to a ticket.

**Warehouse**: receive (adds stock), issue to a job (deducts stock and links to the ticket), count (adjusts stock). Reaching the reorder level alerts procurement.

**Fleet repair**: open a job (vehicle, type, worker, garage, expected hours) → the worker presses *Start repair* (the dial runs) → finish with the cost. Expiring registration (Daftar) and insurance trigger reminders.

**Rent**: Mark paid (amount, date, method, reference → receipt number). Bulk import CSV columns: `unit_code, month (YYYY-MM), amount, paid_on (YYYY-MM-DD), method, reference`. Rent more than 5 days overdue appears in reminders. *Send reminders* (`sendReminders`) is available.

**Building set-up**: Add building (name, category: Residential, Commercial, Office, Retail, Industrial & Logistics, Mixed Portfolio; country; address; supervisor; guard). The country's document checklist is created automatically; for Kuwait it covers the title deed, municipality permit, KFSD fire certificate, PACI, MEW, insurance and lift certificate. So is the planned-maintenance schedule. The floor builder takes from floor, to floor, units per floor, type, rental or lease, area and rent. A guard account is created for each new building.

## 6. Reports

- Jobs raised vs closed over time
- Percentage of jobs fixed within the deadline (SLA compliance)
- Where jobs wait longest in the approval chain (average time per stage)
- Cost by category
- Technician performance (jobs, average time, on-time rate)
- Pending vs done per building
- Repair times: expected vs actual hours by job type and garage (fleet)
- Occupancy and rent collection
- Audit trail
- **CSV export** for Excel on the report and rent tables

## 7. Roles and the permission matrix

The roles set the defaults. An administrator can tick or untick any module or action for an individual user. Supervisors and guards only see their assigned buildings.

**Modules**

| Module | Admin | Owner | Manager | Supervisor | Procurement | Technician | Guard |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| Dashboard | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | |
| Late jobs & escalations | ✓ | ✓ | ✓ | ✓ | | | |
| Buildings | ✓ | ✓ | ✓ | ✓ | | | |
| Units & leases | ✓ | ✓ | ✓ | ✓ | | | |
| Tenants | ✓ | ✓ | ✓ | ✓ | | | |
| Vacant inspections | ✓ | ✓ | ✓ | ✓ | | | ✓ |
| Maintenance | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Report an issue | ✓ | | ✓ | ✓ | | | ✓ |
| Guard tools | ✓ | | | | | | ✓ |
| Warehouse | ✓ | ✓ | ✓ | | ✓ | ✓ | |
| Fleet | ✓ | ✓ | ✓ | | ✓ | ✓ | |
| Rent collection | ✓ | ✓ | | ✓ | | | |
| Alerts & messages | ✓ | ✓ | ✓ | ✓ | | | |
| Reports | ✓ | ✓ | ✓ | | ✓ | | |
| Users & permissions | ✓ | | | | | | |
| Settings | ✓ | | | | | | |
| Live wall | ✓ | ✓ | ✓ | | | | |
| Help & guide | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

**Actions**

| Action | Admin | Owner | Manager | Supervisor | Procurement | Technician | Guard |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| editProperty: add and edit buildings, units, documents | ✓ | | | | | | |
| editTenant: tenants and leases | ✓ | | | ✓ | | | |
| createTicket | ✓ | | ✓ | ✓ | | | ✓ |
| supApprove: supervisor pre-approval | ✓ | | | ✓ | | | |
| mgrApprove: manager approval | ✓ | | ✓ | | | | |
| ownerApprove: final approval | ✓ | ✓ | | | | | |
| completeJob: record job done | ✓ | | | | | ✓ | |
| closeJob: close or send to procurement | ✓ | ✓ | ✓ | | | | |
| procure: approve purchases | ✓ | | | | ✓ | | |
| inspect: carry out inspections | ✓ | | ✓ | ✓ | | | ✓ |
| reviewInspection | ✓ | ✓ | ✓ | | | | |
| stockEdit: add items, receive goods | ✓ | | | | ✓ | | |
| stockIssue: issue stock to jobs | ✓ | | ✓ | | ✓ | ✓ | |
| fleetEdit: vehicles, open repair jobs | ✓ | | ✓ | | | | |
| fleetWork: work on repair jobs | ✓ | | | | | ✓ | |
| markPaid: rent paid, CSV import | ✓ | | | | | | |
| sendReminders | ✓ | | ✓ | ✓ | | | |
| manageSettings | ✓ | | | | | | |

The source of truth is `ROLES` in `public/app.js`.

## 8. Notifications and alerts

- **In-app** notifications (`notifs` table) are shown in the bell.
- **Email and WhatsApp** messages are written to the `outbox` table. The `aqar-alerts` Edge Function sends them (Resend for email, Twilio for WhatsApp) every 5 minutes. Without keys they wait as *waiting for sending keys*.
- Each user can switch off email or WhatsApp in their profile, and the admin can switch a channel off for everyone in Settings.
- Escalation state per job is kept in the `alerts` table (count, first and last alert, resolved).

## 9. Settings (defaults)

| Setting | Default |
|---|---|
| Urgent/Emergency fix deadline | 24 h |
| Normal/Planned fix deadline | 48 h |
| Late-job alert repeat | 4 h |
| Vehicle over-time alert repeat | 2 h |
| Escalation roles | supervisor, manager, owner, admin |
| Owner approval limit | 0 (owner approves every job) |
| Channels | email, WhatsApp, in-app on |
| Low-stock alerts | on |
| Organisation name | Alkazemi Asset Management |
