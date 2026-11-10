# Demo: Direction A, Briefing

**Start:** `/a-briefing.html`

One page read top to bottom: what needs you first, grouped by the move it asks for, then every epic in priority order with its state in one bar, opening in place. A sample board; the actions are inert.

## Steps

1. **One sentence says what needs you, and how much**
   `waitFor #glance h1`
   `wait 3400`
   _Prove:_ the glance names what needs you — `text #glance h1 ~ "need you"`

2. **What needs you comes first, grouped by the move it asks for**
   `scroll #needs .group`
   `wait 3400`
   _Prove:_ the decisions lead — `visible #needs .group .verb.v-decide`

3. **Alike asks fold into one line, and one click shows each**
   `click [data-cluster-toggle]`
   `wait 3400`
   _Prove:_ the folded asks open — `visible .members.open .row`

4. **An ask opens beside the page, with its actions and a resting terminal**
   `click #needs .row[data-open]`
   `wait 3400`
   _Prove:_ the detail is open — `visible #drawer.open .detail`

5. **Go live attaches the terminal to the session behind it**
   `click #drawer [data-golive]`
   `wait 3400`
   _Prove:_ the terminal is live — `visible #drawer .term .st.live`

6. **Escape closes it, and the page is where you left it**
   `press Escape`
   `wait 3400`
   _Prove:_ the detail is closed — `hidden #drawer.open`

7. **Where things stand: every epic in priority order, its state in one bar**
   `scroll #stand`
   `wait 3400`
   _Prove:_ the epics show — `count #stand .area-head >= 10`

8. **An epic opens in place: its work grouped by state, what landed folded away**
   `click .area-head:has-text("Built-once migration")`
   `wait 3400`
   _Prove:_ the epic is open — `visible #stand .area.open .area-body h4`

9. **Work in no epic folds by rig, alike rows piled into one line**
   `scroll #loose`
   `click #loose .area-head:has-text("gc-toolkit")`
   `wait 3400`
   _Prove:_ the pile shows — `visible #loose .area.open .item[data-cluster]`

10. **Search narrows the whole page to what matches**
    `type #q ~ checkout`
    `wait 3400`
    _Prove:_ the matching epic shows — `visible .area-head:has-text("Checkout rebuild")`
