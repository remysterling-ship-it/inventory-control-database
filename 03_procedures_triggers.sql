-- Inventory Control Database Management System
-- Stored procedures, trigger functions, and audit automation.
-- Run after 01_schema.sql. The routines assume the tables from that script exist.

-- 1. Audit table for every accepted inventory movement.
CREATE TABLE IF NOT EXISTS inventory_transaction_audit (
    audit_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transaction_id INTEGER NOT NULL REFERENCES inventory_transactions(transaction_id),
    action TEXT NOT NULL CHECK (action IN ('inserted', 'updated')),
    changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by TEXT NOT NULL DEFAULT CURRENT_USER
);

-- 2. Trigger function: apply a movement to the current warehouse quantity.
--    Purchases, deliveries, and returns add stock. Sales and adjustments remove it.
CREATE OR REPLACE FUNCTION apply_inventory_transaction()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    movement INTEGER;
    available_quantity INTEGER;
BEGIN
    movement := CASE
        WHEN NEW.transaction_type IN ('purchase', 'delivery', 'return') THEN NEW.quantity
        WHEN NEW.transaction_type IN ('sale', 'adjustment') THEN -NEW.quantity
    END;

    INSERT INTO warehouse_stock (warehouse_id, item_id, current_quantity, reorder_threshold, reorder_quantity)
    VALUES (NEW.warehouse_id, NEW.item_id, 0, 10, 25)
    ON CONFLICT (warehouse_id, item_id) DO NOTHING;

    SELECT current_quantity
    INTO available_quantity
    FROM warehouse_stock
    WHERE warehouse_id = NEW.warehouse_id
      AND item_id = NEW.item_id
    FOR UPDATE;

    IF available_quantity + movement < 0 THEN
        RAISE EXCEPTION 'Inventory cannot become negative for item % at warehouse %',
            NEW.item_id, NEW.warehouse_id;
    END IF;

    UPDATE warehouse_stock
    SET current_quantity = current_quantity + movement
    WHERE warehouse_id = NEW.warehouse_id
      AND item_id = NEW.item_id;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS apply_inventory_transaction_after_insert ON inventory_transactions;
CREATE TRIGGER apply_inventory_transaction_after_insert
AFTER INSERT ON inventory_transactions
FOR EACH ROW EXECUTE FUNCTION apply_inventory_transaction();

-- 3. Trigger function: write an audit row after a movement is accepted.
CREATE OR REPLACE FUNCTION audit_inventory_transaction()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO inventory_transaction_audit (transaction_id, action)
    VALUES (NEW.transaction_id, lower(TG_OP));
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS audit_inventory_transaction_after_write ON inventory_transactions;
CREATE TRIGGER audit_inventory_transaction_after_write
AFTER INSERT OR UPDATE ON inventory_transactions
FOR EACH ROW EXECUTE FUNCTION audit_inventory_transaction();

-- 4. Stored procedure: record one validated inventory movement.
--    The stock trigger updates warehouse_stock automatically.
CREATE OR REPLACE PROCEDURE record_inventory_transaction(
    p_warehouse_id INTEGER,
    p_item_id INTEGER,
    p_transaction_type TEXT,
    p_quantity INTEGER,
    p_price NUMERIC(12, 2),
    p_reference_note TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_transaction_type NOT IN ('purchase', 'sale', 'delivery', 'return', 'adjustment') THEN
        RAISE EXCEPTION 'Unsupported inventory transaction type: %', p_transaction_type;
    END IF;

    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Quantity must be a positive integer';
    END IF;

    IF p_price IS NULL OR p_price < 0 THEN
        RAISE EXCEPTION 'Price must be non-negative';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM warehouses WHERE warehouse_id = p_warehouse_id) THEN
        RAISE EXCEPTION 'Warehouse % does not exist', p_warehouse_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM items WHERE item_id = p_item_id AND active = TRUE) THEN
        RAISE EXCEPTION 'Active item % does not exist', p_item_id;
    END IF;

    INSERT INTO inventory_transactions (
        warehouse_id, item_id, transaction_type, quantity, price, reference_note
    ) VALUES (
        p_warehouse_id, p_item_id, p_transaction_type, p_quantity, p_price, p_reference_note
    );
END;
$$;

-- 5. Stored procedure: create one reorder request per low-stock item.
--    Duplicate requests for the same day are ignored by the unique constraint.
CREATE OR REPLACE PROCEDURE generate_reorder_requests()
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO reorder_requests (warehouse_id, item_id, requested_quantity)
    SELECT warehouse_id, item_id, reorder_quantity
    FROM warehouse_stock
    WHERE current_quantity <= reorder_threshold
    ON CONFLICT (warehouse_id, item_id, requested_on) DO NOTHING;
END;
$$;

-- 6. Stored procedure: receive a previously requested reorder.
--    It records the delivery, marks the request received, and relies on the
--    inventory trigger to increase current stock.
CREATE OR REPLACE PROCEDURE receive_reorder(
    p_reorder_id INTEGER,
    p_price NUMERIC(12, 2),
    p_reference_note TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    request_row reorder_requests%ROWTYPE;
BEGIN
    SELECT *
    INTO request_row
    FROM reorder_requests
    WHERE reorder_id = p_reorder_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reorder request % does not exist', p_reorder_id;
    END IF;

    IF request_row.status NOT IN ('requested', 'ordered') THEN
        RAISE EXCEPTION 'Reorder request % has status % and cannot be received',
            p_reorder_id, request_row.status;
    END IF;

    CALL record_inventory_transaction(
        request_row.warehouse_id,
        request_row.item_id,
        'delivery',
        request_row.requested_quantity,
        p_price,
        COALESCE(p_reference_note, 'Received reorder ' || p_reorder_id)
    );

    UPDATE reorder_requests
    SET status = 'received'
    WHERE reorder_id = p_reorder_id;
END;
$$;

-- 7. Helpful operational view for API and reporting consumers.
CREATE OR REPLACE VIEW inventory_reorder_status AS
SELECT
    ws.warehouse_id,
    w.warehouse_name,
    ws.item_id,
    i.item_name,
    ws.current_quantity,
    ws.reorder_threshold,
    ws.reorder_quantity,
    CASE
        WHEN ws.current_quantity = 0 THEN 'urgent'
        WHEN ws.current_quantity <= ws.reorder_threshold THEN 'reorder'
        ELSE 'healthy'
    END AS stock_status
FROM warehouse_stock ws
JOIN warehouses w ON w.warehouse_id = ws.warehouse_id
JOIN items i ON i.item_id = ws.item_id;

-- Example calls (execute intentionally, after reviewing the values):
-- CALL record_inventory_transaction(1, 1, 'purchase', 10, 3000, 'Routine restock');
-- CALL generate_reorder_requests();
-- CALL receive_reorder(1, 3000, 'Supplier delivery received');
-- SELECT * FROM inventory_reorder_status ORDER BY stock_status, item_name;
-- SELECT * FROM inventory_transaction_audit ORDER BY changed_at DESC;
