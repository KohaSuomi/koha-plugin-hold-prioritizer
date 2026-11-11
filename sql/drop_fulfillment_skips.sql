-- Drop columns and system preferences no longer used now that local holds
-- priority is handled by the HoldPrioritizer plugin (KohaSuomi #1563).
-- Run against the Koha database, e.g.:
--   mysql -u koha -p koha < drop_fulfillment_skips.sql

ALTER TABLE reserves DROP COLUMN IF EXISTS fulfillment_skips;
ALTER TABLE old_reserves DROP COLUMN IF EXISTS fulfillment_skips;

DELETE FROM systempreferences WHERE variable IN (
    'LocalHoldsPriorityFulfillmentSkips',
    'LocalHoldsPriorityHoldsPerItemThreshold',
    'LocalHoldsPriorityItemsAgainstHoldsRatio',
    'LocalHoldsPriorityMaxHolds',
    'LocalHoldsPriorityMinItems'
);