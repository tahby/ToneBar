# ToneBar Eval Results

- Machine: Apple M5 Pro
- macOS: Version 27.0 (Build 26A428)
- Bundle: LayaKit/models/ane (ANE)
- Date: 2026-09-21
- SST-2 dataset size: 872 (Laya skipped: 0)
- Handset dataset size: 60, non-English subset: 10 (Laya skipped: 0)
- Latency batch: 60 handset items

## SST-2 (binary, threshold 0)

| scorer | n | accuracy | macro-F1 |
|---|---|---|---|
| NLTone | 872 | 64.8% | 62.7% |
| LayaKit (ANE) | 872 | 79.9% | 79.7% |
| LayaKit (General) | 872 | 79.7% | 79.5% |

## Handset (3-class, ±0.2 thresholds)

| scorer | n | accuracy |
|---|---|---|
| NLTone | 60 | 43.3% |
| LayaKit | 60 | 63.3% |
| LayaKit (argmax) | 60 | 70.0% |

### NLTone confusion matrix

| true \ pred | negative | neutral | positive |
|---|---|---|---|
| negative | 10 | 7 | 3 |
| neutral | 14 | 5 | 1 |
| positive | 5 | 4 | 11 |

### LayaKit confusion matrix

| true \ pred | negative | neutral | positive |
|---|---|---|---|
| negative | 18 | 0 | 2 |
| neutral | 14 | 5 | 1 |
| positive | 1 | 4 | 15 |

### LayaKit (argmax) confusion matrix

| true \ pred | negative | neutral | positive |
|---|---|---|---|
| negative | 18 | 1 | 1 |
| neutral | 7 | 12 | 1 |
| positive | 1 | 7 | 12 |

## Non-English subset (10 items, 3-class)

| scorer | n | accuracy |
|---|---|---|
| NLTone | 10 | 30.0% |
| LayaKit | 10 | 70.0% |

## Agreement between NLTone and LayaKit

| dataset | n | agreement |
|---|---|---|
| SST-2 (2-class) | 872 | 70.6% |
| Handset (3-class) | 60 | 50.0% |

## Latency (p50, 1 warm-up call discarded)

| scorer | p50 |
|---|---|
| NLTone | 1.03 ms |
| LayaKit | 6.41 ms |

## Top 10 handset disagreements (by |score difference|)

| text | true label | NLTone score | LayaKit score |
|---|---|---|---|
| Oh fantastic, the printer broke again right before my deadline. | negative | 1.000 | -0.989 |
| Quarterly revenue increased by 4% compared to the previous period. | neutral | -0.600 | 0.996 |
| I am absolutely furious about how this was handled. | negative | 0.600 | -0.994 |
| Not bad at all, actually pretty impressive work here. | positive | -0.400 | 0.661 |
| Este es el peor servicio que he recibido jamás, una vergüenza total. | negative | 0.000 | -0.998 |
| Das war eine absolute Katastrophe, ich bin wirklich enttäuscht. | negative | 0.000 | -0.998 |
| 这真是太糟糕了，我非常失望。 | negative | 0.000 | -0.998 |
| هذه أسوأ خدمة تلقيتها على الإطلاق، خيبة أمل كبيرة. | negative | 0.000 | -0.994 |
| This laptop is decent for the price, though the battery life is mediocre and the screen is gorgeous. | neutral | -1.000 | -0.006 |
| 😡💔 | negative | 0.000 | -0.993 |
