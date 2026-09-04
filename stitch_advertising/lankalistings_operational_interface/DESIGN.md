---
name: LankaListings Operational Interface
colors:
  surface: '#f7f9fb'
  surface-dim: '#d8dadc'
  surface-bright: '#f7f9fb'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f4f6'
  surface-container: '#eceef0'
  surface-container-high: '#e6e8ea'
  surface-container-highest: '#e0e3e5'
  on-surface: '#191c1e'
  on-surface-variant: '#45464d'
  inverse-surface: '#2d3133'
  inverse-on-surface: '#eff1f3'
  outline: '#76777d'
  outline-variant: '#c6c6cd'
  surface-tint: '#565e74'
  primary: '#000000'
  on-primary: '#ffffff'
  primary-container: '#131b2e'
  on-primary-container: '#7c839b'
  inverse-primary: '#bec6e0'
  secondary: '#515f74'
  on-secondary: '#ffffff'
  secondary-container: '#d5e3fc'
  on-secondary-container: '#57657a'
  tertiary: '#000000'
  on-tertiary: '#ffffff'
  tertiary-container: '#002113'
  on-tertiary-container: '#009668'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#dae2fd'
  primary-fixed-dim: '#bec6e0'
  on-primary-fixed: '#131b2e'
  on-primary-fixed-variant: '#3f465c'
  secondary-fixed: '#d5e3fc'
  secondary-fixed-dim: '#b9c7df'
  on-secondary-fixed: '#0d1c2e'
  on-secondary-fixed-variant: '#3a485b'
  tertiary-fixed: '#6ffbbe'
  tertiary-fixed-dim: '#4edea3'
  on-tertiary-fixed: '#002113'
  on-tertiary-fixed-variant: '#005236'
  background: '#f7f9fb'
  on-background: '#191c1e'
  surface-variant: '#e0e3e5'
typography:
  display-lg:
    fontFamily: Manrope
    fontSize: 30px
    fontWeight: '700'
    lineHeight: 38px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Manrope
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.01em
  title-sm:
    fontFamily: Manrope
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  body-md:
    fontFamily: Manrope
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Manrope
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
  label-caps:
    fontFamily: Manrope
    fontSize: 11px
    fontWeight: '700'
    lineHeight: 16px
    letterSpacing: 0.05em
  data-mono:
    fontFamily: Manrope
    fontSize: 14px
    fontWeight: '500'
    lineHeight: 20px
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  base: 4px
  container-padding: 24px
  gutter: 16px
  sidebar-width: 260px
  sidebar-collapsed: 72px
  table-row-height: 48px
  stack-compact: 8px
  stack-loose: 16px
---

## Brand & Style

The design system is engineered for high-utility, high-density administrative workflows. The aesthetic is **Corporate / Modern**, prioritizing information hierarchy and visual clarity over decorative elements. It targets professional moderators and administrators who require a stable, predictable, and low-friction environment for rapid decision-making.

The visual narrative is built on the principle of "Objective Clarity." This is achieved through:
- **Functional Minimalism:** Removing non-essential ornamentation to focus on data.
- **Systematic Order:** Rigorous alignment and consistent spatial patterns that facilitate scanning.
- **Semantic Precision:** Using color and typography not for flair, but to communicate status and urgency instantly.
- **Desktop Optimization:** Leveraging the horizontal real estate of professional monitors to minimize scrolling and maximize context.

## Colors

The palette is anchored in **Deep Navy (#0F172A)**, providing a high-contrast foundation for navigation and structural headers. This creates a clear mental model of "the frame" versus "the content." 

The content surface uses **#F8FAFC** (Slate 50) to significantly reduce the glare associated with pure white backgrounds, essential for long-form moderation sessions. 

Functional colors are strictly reserved for state-driven communication:
- **Emerald (#10B981)**: Indicates active listings, growth, and successful operations.
- **Amber (#F59E0B)**: Signals pending reviews or items requiring attention.
- **Red (#EF4444)**: Reserved for flagged content, deletions, and critical errors.
- **Slate (#475569)**: Used for secondary metadata and inactive states to keep them visually subordinate.

## Typography

The design system utilizes **Manrope** for its exceptional legibility and modern geometric construction. 

A critical implementation detail for this system is the use of **Tabular Numerals** (`tabular-nums`) for all data points within tables and metric cards. This ensures that columns of numbers align vertically, allowing moderators to compare values across rows instantly.

- **Headlines:** Use tighter letter-spacing and heavier weights to anchor page sections.
- **Body Text:** Standardized at 14px for optimal density; 13px is used for secondary metadata.
- **Labels:** Uppercase labels are used for table headers and section overviews to differentiate structural text from user-generated content.

## Layout & Spacing

The layout follows a **Fixed-Fluid hybrid model** designed for professional desktop use. 

1.  **Navigation:** A vertical collapsible sidebar on the left provides primary navigation. It maintains a fixed width (260px) to preserve text labels but can be collapsed to an icon-only view (72px) to maximize data workspace.
2.  **Grid:** The main content area uses a fluid grid with a 24px outer margin. 
3.  **Density:** Spacing is built on a 4px baseline grid. For moderation tasks, we prioritize a "Compact" rhythm. Table rows are set to a fixed 48px height to maintain density while remaining clickable.
4.  **Breakpoints:** 
    - **Desktop (1440px+):** Full multi-column dashboard.
    - **Laptop (1024px - 1439px):** Sidebar remains expanded; fluid content.
    - **Tablet (Under 1024px):** Sidebar collapses automatically; horizontal table scrolling enabled.

## Elevation & Depth

This design system avoids heavy shadows and skeuomorphism to maintain a professional, flat aesthetic. Depth is communicated primarily through **Tonal Layering** and **Subtle Outlines**.

- **Level 0 (Background):** The base surface is #F8FAFC.
- **Level 1 (Cards/Containers):** White (#FFFFFF) surfaces with a 1px border of #E2E8F0. No shadow is used for standard cards to maintain a clean, grid-like appearance.
- **Level 2 (Modals/Popovers):** White surface with a very subtle, diffused shadow (0px 4px 12px rgba(15, 23, 42, 0.08)) to indicate temporary interaction layers.
- **Active State:** Elements like selected sidebar items or active tabs use a subtle left-accent border (Emerald or Navy) rather than elevation change.

## Shapes

The shape language is **Soft (0.25rem)**. This subtle rounding softens the clinical nature of an admin portal without appearing "bubbly" or consumer-focused.

- **Standard Elements (Buttons, Inputs, Cards):** 4px (0.25rem) radius.
- **Status Chips:** 100px (Pill-shaped) to clearly distinguish them from interactive buttons.
- **Data Points/Markers:** Square or slightly rounded (2px) for sparklines and chart nodes to maintain the technical feel.

## Components

### Data Tables
The core of the system. Tables must feature:
- Sticky headers for long lists.
- Zebra striping (Background: #F1F5F9) on hover only.
- Fixed-width columns for status badges and actions.
- Inline "Quick Action" buttons that appear on row hover.

### Metric Cards
Containers for KPIs featuring a large "data-mono" value, a small percentage trend indicator (Emerald for up, Red for down), and a simplified sparkline graph using a 2px stroke.

### Status Chips
High-visibility markers for moderation states.
- **Approved:** Emerald background (10% opacity) with Emerald text.
- **Pending:** Amber background (10% opacity) with Amber text.
- **Rejected:** Red background (10% opacity) with Red text.

### Bulk Action Toolbar
A horizontal bar that slides in at the bottom of the viewport when one or more table rows are selected. It uses the Deep Navy (#0F172A) background with white text and icons for high contrast and immediate visibility.

### Inputs & Search
Search fields must include a leading icon (Slate) and a "Command + K" keyboard shortcut hint. Use a 1px border (#E2E8F0) that shifts to Deep Navy on focus.