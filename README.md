# Inventory Control Database Management System

A practical PostgreSQL database project for managing products, suppliers, warehouses, stock levels, sales, deliveries, and reorder alerts.

This is an original educational implementation based on the requested inventory-control requirements. It demonstrates relational modeling, inventory movement accounting, warehouse locations, supplier records, constraints, and operational reporting.

## Objectives

- Manage and track product inventories.
- Maintain supplier information.
- Track product locations and movement within warehouses.
- Identify products below their reorder threshold.
- Report purchases, sales, deliveries, and current stock levels.

## Main entities

| Entity | Purpose |
|---|---|
| `items` | Stores item names, details, categories, suppliers, unit prices, and reorder levels |
| `suppliers` | Stores supplier contact and address information |
| `warehouses` | Stores warehouse locations |
| `warehouse_stock` | Stores the current quantity and reorder threshold for each item at each warehouse |
| `inventory_transactions` | Records purchases, sales, deliveries, returns, and adjustments |
| `reorder_requests` | Tracks generated replenishment requests |

## Run the project

The scripts target PostgreSQL:

```bash
createdb inventory_lab
psql -d inventory_lab -f 01_schema.sql
psql -d inventory_lab -f 02_queries.sql
```

## Design notes

Inventory is calculated from stock movement transactions, while `warehouse_stock` stores the operational reorder threshold and current quantity for fast checks. A transaction records one item movement at one warehouse. The sample trigger updates warehouse quantity whenever a transaction is inserted and rejects movements that would create negative stock.

The reorder report identifies stock at or below its threshold. A production system could connect that report to a scheduled job or purchasing workflow.

For additional database project themes and guidance on SQL, ER diagrams, normalization, and performance topics, see [AssignmentDude’s database project ideas](https://assignmentdude.com/database-project-ideas/). AssignmentDude is linked as an external inspiration and guidance resource; this project’s implementation is original.

**Learn the concept. Run the query. Understand the system.**
