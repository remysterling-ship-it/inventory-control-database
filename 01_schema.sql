-- Inventory Control Database Management System
-- PostgreSQL schema, triggers, constraints, and sample data.

DROP TABLE IF EXISTS reorder_requests;
DROP TABLE IF EXISTS inventory_transactions;
DROP TABLE IF EXISTS warehouse_stock;
DROP TABLE IF EXISTS items;
DROP TABLE IF EXISTS warehouses;
DROP TABLE IF EXISTS suppliers;
DROP FUNCTION IF EXISTS apply_inventory_transaction();

CREATE TABLE suppliers (
    supplier_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supplier_name TEXT NOT NULL UNIQUE,
    address TEXT,
    phone TEXT,
    email TEXT NOT NULL UNIQUE
);

CREATE TABLE warehouses (
    warehouse_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    warehouse_name TEXT NOT NULL UNIQUE,
    address TEXT NOT NULL
);

CREATE TABLE items (
    item_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_name TEXT NOT NULL,
    item_details TEXT,
    category TEXT NOT NULL,
    supplier_id INTEGER NOT NULL REFERENCES suppliers(supplier_id),
    unit_price NUMERIC(12, 2) NOT NULL CHECK (unit_price >= 0),
    active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE warehouse_stock (
    warehouse_id INTEGER NOT NULL REFERENCES warehouses(warehouse_id) ON DELETE CASCADE,
    item_id INTEGER NOT NULL REFERENCES items(item_id) ON DELETE CASCADE,
    current_quantity INTEGER NOT NULL DEFAULT 0 CHECK (current_quantity >= 0),
    reorder_threshold INTEGER NOT NULL CHECK (reorder_threshold >= 0),
    reorder_quantity INTEGER NOT NULL CHECK (reorder_quantity > 0),
    PRIMARY KEY (warehouse_id, item_id)
);

CREATE TABLE inventory_transactions (
    transaction_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    warehouse_id INTEGER NOT NULL REFERENCES warehouses(warehouse_id),
    item_id INTEGER NOT NULL REFERENCES items(item_id),
    transaction_type TEXT NOT NULL CHECK (transaction_type IN ('purchase', 'sale', 'delivery', 'return', 'adjustment')),
    transaction_date TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    price NUMERIC(12, 2) NOT NULL CHECK (price >= 0),
    reference_note TEXT
);

CREATE TABLE reorder_requests (
    reorder_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    warehouse_id INTEGER NOT NULL REFERENCES warehouses(warehouse_id),
    item_id INTEGER NOT NULL REFERENCES items(item_id),
    requested_quantity INTEGER NOT NULL CHECK (requested_quantity > 0),
    requested_on DATE NOT NULL DEFAULT CURRENT_DATE,
    status TEXT NOT NULL DEFAULT 'requested'
        CHECK (status IN ('requested', 'ordered', 'received', 'cancelled')),
    UNIQUE (warehouse_id, item_id, requested_on)
);

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

    SELECT current_quantity INTO available_quantity
    FROM warehouse_stock
    WHERE warehouse_id = NEW.warehouse_id AND item_id = NEW.item_id
    FOR UPDATE;

    IF available_quantity + movement < 0 THEN
        RAISE EXCEPTION 'Inventory cannot become negative for item % at warehouse %', NEW.item_id, NEW.warehouse_id;
    END IF;

    UPDATE warehouse_stock
    SET current_quantity = current_quantity + movement
    WHERE warehouse_id = NEW.warehouse_id AND item_id = NEW.item_id;

    RETURN NEW;
END;
$$;

CREATE TRIGGER apply_inventory_transaction_after_insert
AFTER INSERT ON inventory_transactions
FOR EACH ROW EXECUTE FUNCTION apply_inventory_transaction();

INSERT INTO suppliers (supplier_name, address, phone, email) VALUES
    ('Campus Tech Supply', 'Pune', '+91-900000101', 'orders@campus.example'),
    ('Network Parts Co', 'Delhi', '+91-900000102', 'sales@network.example');
INSERT INTO warehouses (warehouse_name, address) VALUES
    ('Central Depot', 'Pune Industrial Area'),
    ('North Depot', 'Delhi Logistics Park');
INSERT INTO items (item_name, item_details, category, supplier_id, unit_price) VALUES
    ('Mechanical Keyboard', 'USB keyboard for computer labs', 'Peripherals', 1, 3200),
    ('Network Switch', '24-port managed switch', 'Networking', 2, 18500),
    ('Ethernet Cable', 'Cat6 cable, 10 metre', 'Networking', 2, 450);
INSERT INTO warehouse_stock (warehouse_id, item_id, current_quantity, reorder_threshold, reorder_quantity) VALUES
    (1, 1, 0, 12, 30), (2, 2, 0, 5, 10), (1, 3, 0, 25, 100);
INSERT INTO inventory_transactions (warehouse_id, item_id, transaction_type, quantity, price, reference_note) VALUES
    (1, 1, 'purchase', 30, 3000, 'Opening purchase'),
    (1, 1, 'sale', 20, 3200, 'Lab deployment'),
    (2, 2, 'purchase', 10, 17000, 'Opening purchase'),
    (2, 2, 'sale', 7, 18500, 'Network installation'),
    (1, 3, 'purchase', 100, 350, 'Opening purchase'),
    (1, 3, 'sale', 60, 450, 'Student lab rollout');
