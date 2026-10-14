# Accountable design direction

## Product feel

Accountable should feel like a calm, trustworthy native finance app rather than a spreadsheet dashboard.

The interface should be:

- Clear and information-dense without feeling crowded.
- Calm and restrained, with purposeful use of color.
- Fast to scan on a phone.
- Comfortable to use with one hand.
- Equally usable in a wide desktop browser.
- Honest about loading, stale data, errors, and incomplete information.

## Visual direction

Use a light-first visual system with:

- Deep navy as the primary brand and navigation color.
- Teal and green for positive financial states and progress.
- Red only for negative values, warnings, destructive actions, or errors.
- Neutral white cards on a very light background.
- Subtle borders instead of heavy shadows.
- Rounded, practical surfaces rather than decorative shapes.

Color should communicate meaning, not decorate every element. Positive and negative colors must not be the only way information is conveyed; pair them with labels, icons, or signs.

## Information hierarchy

Every screen should make the most important answer obvious first.

- Overview: current financial position and recent movement.
- Transactions: quick scanning, filtering, and entry.
- Accounts: balances, currencies, and account status.
- Analysis: trends, comparisons, and breakdowns.
- Settings: configuration, data source, and reload/error actions.

Use progressive disclosure for secondary details. Prefer a short summary followed by an intentional path to deeper data.

## Mobile-first behavior

- Design compact layouts first, then expand them for desktop.
- Use bottom navigation on compact widths.
- Use a navigation rail or sidebar on wider layouts.
- Keep primary actions reachable and visually prominent.
- Use bottom sheets or full-screen flows for filters and forms on mobile.
- Use larger touch targets and avoid dense spreadsheet-like controls.
- Preserve context when navigating back from details or forms.

## Desktop behavior

Desktop layouts may use additional horizontal space for:

- Persistent navigation.
- Multi-column summaries.
- Wider charts.
- Side-by-side filters and detail panels.

Desktop should not become a separate product. It should present the same hierarchy with more breathing room.

## Components and patterns

Prefer shared components for repeated patterns:

- Metric cards.
- Account rows.
- Transaction rows.
- Date-range controls.
- Filter chips.
- Empty and error states.
- Confirmation and submission feedback.

Keep visual decisions in the central theme and design tokens rather than scattering colors, spacing, and radii through feature widgets.

## Interaction principles

- Make the common action fast.
- Make destructive or irreversible actions explicit.
- Show what period and currency a number represents.
- Do not hide stale or unavailable data.
- Avoid optimistic updates when a failed financial write could create confusion.
- Confirm successful transaction submission clearly.

## Scope of this document

This document preserves the product’s visual intent and interaction principles. It should guide future redesigns without prescribing exact screen layouts, pixel values, or individual widget implementations.

Executable values such as colors, spacing, breakpoints, and component theme settings live in [`lib/app/theme/`](./lib/app/theme/).
