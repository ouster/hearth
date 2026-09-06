---
id: 03-refactor-judgment
category: reasoning
auto_check: none
---

Here is a function. Identify every bug, then give a corrected version.

```python
def apply_discount(items, discount_pct):
    total = 0
    for i in range(len(items)):
        total += items[i]['price'] * items[i]['qty']
    if discount_pct > 0:
        total = total - (total * discount_pct / 100)
    return round(total, 2)
```

Context: this is used for money totals in a billing system, so
correctness of the arithmetic matters more than elegance.

Be specific about what breaks and under what input. Judged on whether it catches
the float-for-currency problem, not just the obvious style issues.
