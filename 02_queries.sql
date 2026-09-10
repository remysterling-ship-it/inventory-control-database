-- Inventory Control Database query exercises.
-- Run after 01_schema.sql.

-- 1. Search active items by category or name.
SELECT i.item_id, i.item_name, i.category, s.supplier_name, i.unit_price
FROM items i
JOIN suppliers s ON s.supplier_id = i.supplier_id
WHERE i.active = TRUE
  AND (i.item_name ILIKE '%network%' OR i.category = 'Peripherals')
ORDER BY i.item_name;

-- 2. Current stock by warehouse and item.
SELECT w.warehouse_name, i.item_name,
       ws.current_quantity,
       ws.reorder_threshold,
       ws.reorder_quantity
FROM warehouse_stock ws
JOIN warehouses w ON w.warehouse_id = ws.warehouse_id
JOIN items i ON i.item_id = ws.item_id
ORDER BY w.warehouse_name, i.item_name;

-- 3. Items at or below their reorder threshold.
SELECT w.warehouse_name, i.item_name,
       ws.current_quantity,
       ws.reorder_threshold,
       ws.reorder_quantity,
       CASE WHEN ws.current_quantity = 0 THEN 'urgent' ELSE 'reorder' END AS action
FROM warehouse_stock ws
JOIN warehouses w ON w.warehouse_id = ws.warehouse_id
JOIN items i ON i.item_id = ws.item_id
WHERE ws.current_quantity <= ws.reorder_threshold
ORDER BY action DESC, w.warehouse_name;

-- 4. Movement summary by item and transaction type.
SELECT i.item_name,
       it.transaction_type,
       SUM(it.quantity) AS units,
       SUM(it.quantity * it.price) AS movement_value
FROM inventory_transactions it
JOIN items i ON i.item_id = it.item_id
GROUP BY i.item_id, i.item_name, it.transaction_type
ORDER BY i.item_name, it.transaction_type;

-- 5. Generate one reorder request for each item currently below threshold.
-- The conflict rule prevents duplicate requests on the same day.
INSERT INTO reorder_requests (warehouse_id, item_id, requested_quantity)
SELECT warehouse_id, item_id, reorder_quantity
FROM warehouse_stock
WHERE current_quantity <= reorder_threshold
ON CONFLICT (warehouse_id, item_id, requested_on) DO NOTHING;

-- 6. Review requested replenishment.
SELECT rr.reorder_id, w.warehouse_name, i.item_name,
       rr.requested_quantity, rr.requested_on, rr.status
FROM reorder_requests rr
JOIN warehouses w ON w.warehouse_id = rr.warehouse_id
JOIN items i ON i.item_id = rr.item_id
WHERE rr.status = 'requested'
ORDER BY rr.requested_on, w.warehouse_name;
