# Node.js / Express Inventory API

A small Express backend that connects the inventory schema to HTTP clients through PostgreSQL. It exposes read-only inventory reports and a transaction endpoint for recording stock movements.

## Setup

From this directory:

```bash
npm install
cp .env.example .env
# Edit DATABASE_URL in .env
npm start
```

The default server listens on `http://localhost:3000`.

## Endpoints

| Method | Route | Purpose |
|---|---|---|
| `GET` | `/health` | Check API and database connectivity |
| `GET` | `/api/items` | List items with stock by warehouse |
| `GET` | `/api/reorders` | List items at or below reorder threshold |
| `POST` | `/api/transactions` | Record a purchase, sale, delivery, return, or adjustment |

Example transaction request:

```bash
curl -X POST http://localhost:3000/api/transactions \
  -H 'Content-Type: application/json' \
  -d '{"warehouseId":1,"itemId":1,"transactionType":"purchase","quantity":10,"price":3000,"referenceNote":"Restock"}'
```

The endpoint uses parameterized SQL and validates the request before inserting. The database trigger applies the movement to `warehouse_stock` and rejects a movement that would make stock negative.
