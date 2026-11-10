# Demo: Direction B, Portfolio

**Start:** `/b-portfolio.html`

Every epic as a card in priority order, what needs you in a queue beside them, and a page per epic to dive into. A sample board; the actions are inert.

## Steps

1. **Four answers head the page: needs you, with you, in motion, landed**
   `waitFor .glance`
   `wait 3400`
   _Prove:_ the answers show — `text .g.you ~ "Needs you"`

2. **Every epic is a card that keeps its place, with its state in one bar**
   `waitFor .grid .card`
   `wait 3400`
   _Prove:_ the cards show — `count .grid .card >= 10`

3. **What needs you sits beside them, most important first, alike asks folded**
   `click #rail .q.cluster`
   `wait 3400`
   _Prove:_ the folded asks open — `visible .q-members.open .q`

4. **A click on an epic dives in**
   `click .card:has-text("Built-once migration")`
   `wait 3400`
   _Prove:_ the epic's page shows — `visible .fhead`

5. **Its work in lanes by state, and the queue narrows to this epic**
   `waitFor .lanes`
   `wait 3400`
   _Prove:_ the queue names the epic — `text #rail .rail-h ~ "Built-once migration"`

6. **A sub-epic is one click deeper**
   `click .subrow button`
   `wait 3400`
   _Prove:_ the trail names the parent — `text .crumb ~ "Built-once migration"`

7. **An item opens in the queue's place: its ask, its actions, and its terminal**
   `click .lane.you .k`
   `wait 3400`
   _Prove:_ the detail shows — `visible #rail .detail`

8. **Go live attaches the terminal**
   `click #rail [data-golive]`
   `wait 3400`
   _Prove:_ the terminal is live — `visible #rail .term .st.live`

9. **Escape climbs back out, one level at a time**
   `press Escape`
   `press Escape`
   `wait 3400`
   _Prove:_ the overview is back — `visible .grid .card`

10. **The n key opens the next thing that needs you, wherever it is**
    `press n`
    `wait 3400`
    _Prove:_ the ask is open — `visible #rail .detail`

11. **The conversations with you are one click from the top**
    `press Escape`
    `press Escape`
    `click .g.talks`
    `wait 3400`
    _Prove:_ the record shows — `text #rail .rail-h ~ "Conversations"`
