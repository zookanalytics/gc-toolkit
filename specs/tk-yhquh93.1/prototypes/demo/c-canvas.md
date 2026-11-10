# Demo: Direction C, Canvas

**Start:** `/c-canvas.html`

The June Attention Canvas on today's board: each epic an island whose place, color and emblem stay put, every item a block of its state's color, and zoom as the level of detail. A sample board; the actions are inert.

## Steps

1. **The whole city from altitude: each epic a place, each item a colored block**
   `waitFor .island`
   `wait 3400`
   _Prove:_ the islands show — `count .island >= 15`

2. **What needs you shows amber, and the list beside it names each in order**
   `waitFor .jump .j`
   `wait 3400`
   _Prove:_ the list shows — `visible .jump .j`

3. **Next for you flies to the most important ask and opens it**
   `click #next`
   `wait 900`
   `wait 3400`
   _Prove:_ the ask is open — `visible #panel.open .detail`

4. **Up close, an island reads: its items, its bar, what needs you**
   `wait 600`
   `wait 3400`
   _Prove:_ the selected item has its label — `visible .chip2.sel .lbl`

5. **Next again goes on down the list, and nothing moves on its own**
   `click #next`
   `wait 900`
   `wait 3400`
   _Prove:_ the next ask is open — `visible #panel.open .detail`

6. **Back to the whole city, then straight into one epic by its name**
   `press 0`
   `wait 700`
   `click .flabel:has-text("Checkout rebuild")`
   `wait 900`
   `wait 3400`
   _Prove:_ the island reads up close — `visible .island:has-text("Checkout rebuild") .chip2 .lbl`

7. **An item opens, and its terminal goes live**
   `click .island:has-text("Checkout rebuild") .chip2.s-you`
   `click #panel [data-golive]`
   `wait 3400`
   _Prove:_ the terminal is live — `visible #panel .term .st.live`
