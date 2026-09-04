---
name: LankaListings
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
  secondary: '#006c49'
  on-secondary: '#ffffff'
  secondary-container: '#6cf8bb'
  on-secondary-container: '#00714d'
  tertiary: '#000000'
  on-tertiary: '#ffffff'
  tertiary-container: '#261a00'
  on-tertiary-container: '#a87d00'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#dae2fd'
  primary-fixed-dim: '#bec6e0'
  on-primary-fixed: '#131b2e'
  on-primary-fixed-variant: '#3f465c'
  secondary-fixed: '#6ffbbe'
  secondary-fixed-dim: '#4edea3'
  on-secondary-fixed: '#002113'
  on-secondary-fixed-variant: '#005236'
  tertiary-fixed: '#ffdf9f'
  tertiary-fixed-dim: '#f9bd22'
  on-tertiary-fixed: '#261a00'
  on-tertiary-fixed-variant: '#5c4300'
  background: '#f7f9fb'
  on-background: '#191c1e'
  surface-variant: '#e0e3e5'
typography:
  display-lg:
    fontFamily: Manrope
    fontSize: 48px
    fontWeight: '800'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Manrope
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
  headline-lg-mobile:
    fontFamily: Manrope
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
  headline-md:
    fontFamily: Manrope
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  price-xl:
    fontFamily: Manrope
    fontSize: 24px
    fontWeight: '800'
    lineHeight: 32px
  body-lg:
    fontFamily: Manrope
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-sm:
    fontFamily: Manrope
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-caps:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.05em
  metadata:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 4px
  xs: 8px
  sm: 16px
  md: 24px
  lg: 40px
  xl: 64px
  gutter: 20px
  margin-mobile: 16px
  margin-desktop: 32px
---

## Brand & Style
The design system is built on a foundation of **Corporate Modernism** with a focus on trust and utility. It targets the Sri Lankan marketplace, balancing professional reliability with local accessibility. The aesthetic is clean and systematic, utilizing heavy whitespace and a structured grid to manage high-density listing information. 

The emotional response should be one of "effortless efficiency"—the UI acts as a transparent window into the marketplace, where the content (the listing) is the hero. Visual noise is minimized to ensure that prices, locations, and specifications are immediately legible to users across diverse socio-economic backgrounds.

## Colors
The palette is anchored by **Deep Navy**, conveying authority and security. **Emerald Green** is the primary action color, used strategically for "Post Ad," "Call," or "Chat" buttons to signify growth and opportunity. **Warm Yellow** is reserved for premium highlights—such as featured listings or urgent badges—providing high contrast without being aggressive.

- **Backgrounds:** Clean White (#FFFFFF) for the main canvas, with Subtle Light-Grey (#F8FAFC) used for surface containers like sidebars or secondary backgrounds to define spatial hierarchy.
- **Borders:** A consistent neutral (#E2E8F0) provides structure without visual clutter.

## Typography
This design system uses **Manrope** for its modern, refined geometric qualities, ensuring high legibility for alphanumeric characters—essential for prices and specs. **Inter** is used for smaller labels and utility text due to its exceptional clarity at small scales.

- **Price Hierarchy:** Prices should always be prominent, using `price-xl` and a weight of 800 to ensure they are the first thing a user sees.
- **Localization:** Use standard "Rs." prefix for LKR. Thousands separators are mandatory (e.g., Rs. 250,000).
- **Scale:** On mobile, top-level headlines scale down by 25% to accommodate smaller viewports while maintaining vertical rhythm.

## Layout & Spacing
The layout follows a **Fluid Grid** model with a maximum container width of 1280px. 

- **Desktop (1024px+):** 12-column grid with 20px gutters. Content is centered.
- **Tablet (768px - 1023px):** 8-column grid. Margins shrink to 24px.
- **Mobile (Up to 767px):** 4-column grid. Margins are 16px.
- **Spacing Rhythm:** Use a 4px baseline. Spacing between related items (e.g., price and title) should be `xs` (8px), while spacing between sections should be `lg` (40px).

## Elevation & Depth
This design system avoids heavy shadows to maintain a clean, professional look. It relies on **Low-contrast outlines** and **Tonal layers**.

- **Level 0 (Base):** White (#FFFFFF) background.
- **Level 1 (Cards/Containers):** White background with a 1px border (#E2E8F0). No shadow.
- **Level 2 (Hover/Active):** Subtle ambient shadow (0px 4px 12px rgba(15, 23, 42, 0.05)) and a slight border darken.
- **Level 3 (Modals/Popovers):** Medium diffused shadow (0px 12px 24px rgba(15, 23, 42, 0.1)).

## Shapes
A "Rounded" shape language (0.5rem / 8px) is applied across all primary UI elements to soften the professional tone and make the platform feel more approachable. 

- **Cards & Inputs:** 8px (rounded-md).
- **Buttons:** 8px for standard, or fully rounded (pill) for "Post Ad" to increase prominence.
- **Images:** Listing thumbnails should always use the 8px radius to match the card container.

## Components
- **Buttons:**
  - *Primary:* Emerald background, white text. High-impact for conversion.
  - *Secondary:* Deep Navy background, white text. Used for main site navigation.
  - *Outline:* 1px border (#E2E8F0) with Navy text. Used for filters and secondary actions.
- **Input Fields:** 1px border (#E2E8F0), 8px radius. On focus, the border changes to Emerald with a 2px outer glow.
- **Cards:** White background, 1px border. Metadata (Location, Date) sits at the bottom in `metadata` style with a small icon (map-pin, clock).
- **Chips:** Used for categories and filters. Light-Grey (#F1F5F9) background with Navy text.
- **Mobile Bottom Nav:** Fixed blur background (glassmorphism Lite) with 5 slots. Icons are 24px. "Post Ad" center button is Emerald to draw immediate attention.
- **Category Icons:** Minimalist line-art icons. Use a consistent stroke weight of 1.5px.
- **Loading:** Use skeleton pulses that mirror the card layout structure for a perceived performance boost.