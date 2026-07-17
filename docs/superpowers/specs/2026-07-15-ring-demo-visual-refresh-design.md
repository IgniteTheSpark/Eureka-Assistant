# Ring Demo Visual Refresh Design

## Scope

This pass implements the first half of the approved refresh:

- a dedicated product Hero as the first home screen;
- a second home screen containing optional Ring connection and two always-available mode entries;
- an Obsidian Hardware visual direction using the supplied transparent Ring renders;
- operator-only account setup, while configured demo visitors enter without seeing login;
- no redesign of the internal Flash or Vibe workspaces in this pass.

## Experience Structure

The home route is a two-screen product page. Screen one is presentation-only: restrained copy and a large three-quarter Ring render. Screen two is the demo launcher: a compact Ring readiness area followed by equally prominent Flash and Vibe entries. Ring connection is never a gate; both mode links remain enabled when disconnected.

Flash and Vibe remain dedicated routes. They continue to support their own Ring connection and all existing functional behavior. Their internal stage redesign is explicitly deferred so the user can approve the product-page direction first.

## Authentication Boundary

A configured browser keeps its Eureka token and opens directly into the demo. A browser without a token is sent to an explicitly operator-labeled setup route. Operator Controls provide access to account setup/switching and demo reset. No account credentials are embedded in the repository or frontend bundle.

## Visual System

The direction is Obsidian Hardware: near-black neutral surfaces, restrained warm metallic highlights, crisp typography, and large product imagery. Flash receives a warm-gold identity and Vibe a cool-silver/blue identity. Decorative card chrome is reduced; spacing and alignment establish hierarchy.

The supplied assets are assigned as follows:

- `6.png`: home Hero;
- `4.png`: Ring connection presentation;
- `5.png`: Flash entry;
- `7.png`: Vibe entry;
- `手4.png`: retained for a later wear/scale section, not used in this first half.

All selected assets are copied into `ring-demo/public/ring/` with descriptive ASCII names. Source files remain unchanged.

## Responsive Behavior

Desktop uses asymmetric split compositions. The Hero copy and product render stack on narrow screens; the two mode entries collapse from two columns to one. Images remain contained and never cause horizontal scrolling. Interactive targets remain at least 44px high and focus-visible.

## Acceptance Criteria

- The home page contains a dedicated Hero and a separately identifiable demo launcher section.
- The launcher renders Ring connection controls and both mode links regardless of connection state.
- Supplied Ring artwork replaces CSS placeholder rings on the home page.
- Missing authentication routes to an operator-labeled account setup surface.
- Operator Controls can open account setup without clearing the active token first.
- Existing Flash, Vibe, Ring, reset, and mode-selection behavior remains green.
