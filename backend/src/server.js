import "dotenv/config";
import express from "express";
import pg from "pg";

const { Pool } = pg;
const app = express();
const port = Number(process.env.PORT ?? 3000);
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.SSL === "true" ? { rejectUnauthorized: false } : false
});

app.use(express.json({ limit: "32kb" }));

app.get("/health", async (_request, response) => {
  try {
    await pool.query("SELECT 1");
    response.json({ status: "ok", database: "connected" });
  } catch (error) {
    response.status(503).json({ status: "error", database: "unavailable" });
  }
});

app.get("/api/items", async (_request, response, next) => {
  try {
    const { rows } = await pool.query(`
      SELECT i.item_id AS "itemId",
             i.item_name AS "itemName",
             i.category,
             s.supplier_name AS "supplierName",
             w.warehouse_name AS "warehouseName",
             ws.current_quantity AS "currentQuantity",
             ws.reorder_threshold AS "reorderThreshold"
      FROM warehouse_stock ws
      JOIN items i ON i.item_id = ws.item_id
      JOIN suppliers s ON s.supplier_id = i.supplier_id
      JOIN warehouses w ON w.warehouse_id = ws.warehouse_id
      WHERE i.active = TRUE
      ORDER BY i.item_name, w.warehouse_name
    `);
    response.json({ data: rows });
  } catch (error) {
    next(error);
  }
});

app.get("/api/reorders", async (_request, response, next) => {
  try {
    const { rows } = await pool.query(`
      SELECT w.warehouse_name AS "warehouseName",
             i.item_id AS "itemId",
             i.item_name AS "itemName",
             ws.current_quantity AS "currentQuantity",
             ws.reorder_threshold AS "reorderThreshold",
             ws.reorder_quantity AS "reorderQuantity"
      FROM warehouse_stock ws
      JOIN warehouses w ON w.warehouse_id = ws.warehouse_id
      JOIN items i ON i.item_id = ws.item_id
      WHERE ws.current_quantity <= ws.reorder_threshold
      ORDER BY ws.current_quantity ASC, i.item_name
    `);
    response.json({ data: rows });
  } catch (error) {
    next(error);
  }
});

app.post("/api/transactions", async (request, response, next) => {
  const { warehouseId, itemId, transactionType, quantity, price, referenceNote } = request.body;
  const validTypes = new Set(["purchase", "sale", "delivery", "return", "adjustment"]);
  const numericQuantity = Number(quantity);
  const numericPrice = Number(price);

  if (!Number.isInteger(Number(warehouseId)) || !Number.isInteger(Number(itemId)) ||
      !validTypes.has(transactionType) || !Number.isInteger(numericQuantity) || numericQuantity <= 0 ||
      !Number.isFinite(numericPrice) || numericPrice < 0) {
    return response.status(400).json({
      error: "warehouseId, itemId, transactionType, positive integer quantity, and non-negative price are required"
    });
  }

  try {
    const { rows } = await pool.query(`
      INSERT INTO inventory_transactions
        (warehouse_id, item_id, transaction_type, quantity, price, reference_note)
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING transaction_id AS "transactionId", transaction_date AS "transactionDate"
    `, [Number(warehouseId), Number(itemId), transactionType, numericQuantity, numericPrice, referenceNote ?? null]);
    response.status(201).json({ data: rows[0] });
  } catch (error) {
    next(error);
  }
});

app.use((error, _request, response, _next) => {
  console.error(error);
  response.status(500).json({ error: "Internal server error" });
});

const server = app.listen(port, () => {
  console.log(`Inventory API listening on port ${port}`);
});

const shutdown = async () => {
  server.close(async () => {
    await pool.end();
    process.exit(0);
  });
};

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
