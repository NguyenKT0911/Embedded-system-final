# AI Accelerator Controller FSM

## State Transition Table

| Current State | Condition | Next State | Meaning |
|---|---|---|---|
| IDLE | `start_pulse = 0` | IDLE | Continue waiting for a START command |
| IDLE | `start_pulse = 1` | CHECK | Begin configuration and data validation |
| CHECK | `validation_ok = 1` | RUN | Configuration and input data are valid |
| CHECK | `validation_ok = 0` | ERROR | Invalid configuration or incomplete data |
| RUN | `compute_error = 1` | ERROR | An error occurred during computation |
| RUN | `compute_error = 0 && compute_done = 1` | DONE | Convolution completed successfully |
| RUN | `compute_error = 0 && compute_done = 0` | RUN | Continue convolution processing |
| DONE | `clear_pulse = 0` | DONE | Hold completion status while software reads output |
| DONE | `clear_pulse = 1` | IDLE | Clear status and prepare for a new operation |
| ERROR | `clear_pulse = 0` | ERROR | Hold error status for software inspection |
| ERROR | `clear_pulse = 1` | IDLE | Clear error and prepare for a new operation |

## State Output Table

| State | BUSY | DONE | ERROR | CORE_EN |
|---|---:|---:|---:|---:|
| IDLE  | 0 | 0 | 0 | 0 |
| CHECK | 1 | 0 | 0 | 0 |
| RUN   | 1 | 0 | 0 | 1 |
| DONE  | 0 | 1 | 0 | 0 |
| ERROR | 0 | 0 | 1 | 0 |

## State Transition Priority

- `rst` has the highest priority and forces the controller to IDLE.
- In the RUN state, `compute_error` has higher priority than `compute_done`.
- If no transition condition is satisfied, the FSM remains in its current state.