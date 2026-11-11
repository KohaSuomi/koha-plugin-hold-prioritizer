# Koha-Suomi plugin HoldPrioritizer

HoldPrioritizer is a Koha plugin that implements **local holds priority** as a
plugin instead of patching Koha core. It is the plugin-side counterpart of
KohaSuomi/Koha issue
[#1563](https://github.com/KohaSuomi/Koha/issues/1563).

It requires a small core patch (two plugin hooks) in Koha:
- `prioritize_hold_for_item` in `C4::Reserves::CheckReserves`
- `prioritize_holds_queue` in `C4::HoldsQueue::MapItemsToHoldRequests`

The patch is ~32 lines and lives on the branch
https://github.com/KohaSuomi/Koha-26x/tree/ksdev/ks-0274-KOHA-1563-hold-prioritizer-plugin

## How it works

Koha already ships a `LocalHoldsPriority` feature, but it runs in two places
(`CheckReserves` for real-time returns and `MapItemsToHoldRequests` for the holds
queue) and has no limits or skip handling. This plugin takes over both
decision points through the hooks above and applies the full policy itself:

1. When an item is returned or checked out, `CheckReserves` asks the plugin
   which hold should be preferred. The plugin returns a reserve (or undef) and
   core still applies all of its own eligibility checks (item group, item type,
   branch rules, transfers).
2. When the holds queue is built, `MapItemsToHoldRequests` asks the plugin for
   the preferred order of the pending holds. Core still performs item-level and
   transport-cost matching.

The plugin stores its own settings (mode, patron/item control, max holds, min
items, holds-per-item threshold, fulfillment skips) in `plugin_data`, so it does
not depend on the core `LocalHoldsPriority*` system preferences. When
"Take over core LocalHoldsPriority" is enabled, the plugin sets core's
`LocalHoldsPriority` to `None` so core cannot override its decisions.

## Settings

Configured via the plugin's configuration page (Tools → Plugins →
HoldPrioritizer → Configure):

| Setting | Meaning |
|---|---|
| Mode | `None`, `GiveLibrary`, `GiveLibraryAndGroup`, `GiveLibraryGroup` |
| Patron control | `PickupLibrary` or `HomeLibrary` |
| Item control | `homebranch` or `holdingbranch` |
| Max holds | Only the first N active holds are considered (0 = no limit) |
| Min items | Prioritise only when at least this many items are available (0 = inactive) |
| Holds per item threshold | Prioritise only when holds/available items is at or below this value (0 = inactive) |
| Fulfillment skips | A hold can be skipped this many times before it is fulfilled (0 = inactive) |
| Take over core LocalHoldsPriority | When checked, sets core `LocalHoldsPriority` to `None` |

## Fulfillment skips

When a local hold is promoted but a higher-priority non-local hold is bypassed,
that non-local hold accumulates a skip. Once a hold reaches the configured
number of skips it is fulfilled first (treated as a fulfillment match). Skips
are reset when the hold is cancelled. Skip state is stored in the plugin's own
`..._skips` table, not in Koha's `reserves` table.

## Logging

The plugin writes to its own table `..._log` (timestamp, message). Entries are
written for gating decisions, preferred-hold selection, skip increments, queue
promotions, and configuration changes. Nothing is logged when the mode is `None`.

## Downloading

From the release page you can download the latest `*.kpz` file.

## Installing

Koha's Plugin System allows for you to add additional tools and reports to Koha
that are specific to your library. Plugins are installed by uploading KPZ
(Koha Plugin Zip) packages. A KPZ file is just a zip file containing the perl
files, template files, and any other files necessary to make the plugin work.

The plugin system needs to be turned on by a system administrator.

To set up the Koha plugin system you must first make some changes to your install.

    Change <enable_plugins>0<enable_plugins> to <enable_plugins>1</enable_plugins> in your koha-conf.xml file
    Confirm that the path to <pluginsdir> exists, is correct, and is writable by the web server
    Remember to allow access to plugin directory from Apache

    <Directory <pluginsdir>>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    Restart your webserver

Once set up is complete you will need to alter your UseKohaPlugins system
preference. On the Tools page you will see the Tools Plugins and on the
Reports page you will see the Reports Plugins.

## Configuring

Open Tools → Plugins → HoldPrioritizer → Configure, adjust the settings and
save. The plugin takes over core `LocalHoldsPriority` when the checkbox is set.

## Database cleanup

If you previously used the branch's `fulfillment_skips` column on `reserves` /
`old_reserves`, you can drop it with `sql/drop_fulfillment_skips.sql`.

## Testing

Plugin tests (run from the Koha tree with the plugin installed):

    prove -l Koha/Plugin/Fi/KohaSuomi/HoldPrioritizer/t/prioritize_hold_for_item.t
    prove -l Koha/Plugin/Fi/KohaSuomi/HoldPrioritizer/t/prioritize_holds_queue.t
    prove -l Koha/Plugin/Fi/KohaSuomi/HoldPrioritizer/t/settings.t
    prove -l Koha/Plugin/Fi/KohaSuomi/HoldPrioritizer/t/settings_variations.t
    prove -l Koha/Plugin/Fi/KohaSuomi/HoldPrioritizer/t/skips.t
    prove -l Koha/Plugin/Fi/KohaSuomi/HoldPrioritizer/t/after_hold_action.t
    prove -l Koha/Plugin/Fi/KohaSuomi/HoldPrioritizer/t/equivalence.t

Performance benchmark (opt-in):

    HOLD_PRIORITIZER_PERF=1 prove -l Koha/Plugin/Fi/KohaSuomi/HoldPrioritizer/t/performance.t