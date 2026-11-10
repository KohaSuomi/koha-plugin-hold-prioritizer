-- Drop columns no longer used now that fulfillment skips are handled
-- by the HoldPrioritizer plugin (KohaSuomi #1563).
-- Run against the Koha database, e.g.:
--   mysql -u koha -p koha < drop_fulfillment_skips.sql

ALTER TABLE reserves DROP COLUMN IF EXISTS fulfillment_skips;
ALTER TABLE old_reserves DROP COLUMN IF EXISTS fulfillment_skips;

DELETE FROM systempreferences WHERE variable = 'LocalHoldsPriorityFulfillmentSkips';