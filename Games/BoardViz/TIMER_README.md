# Timer Manager - Usage Guide

A simple timer system that displays elapsed time in **HH:MM:SS** format with Start/Stop button controls.

## Files

- **timer_manager.gd** - Main timer script (flexible, finds or creates UI elements)
- **timer_controller.gd** - Alternative timer script (creates all UI automatically)
- **timer_example.tscn** - Example scene showing proper setup

## Quick Start (Option 1: Use timer_example.tscn)

1. Open Godot and add the timer_example scene to your main scene
2. The timer will appear in the top-center of the screen
3. Click "Start" button to begin timing
4. Click "Stop" button to pause
5. Call `reset_timer()` from code to reset to 00:00:00

## Manual Setup (Option 2: Add to existing scene)

### Step 1: Create the Node Structure

```
YourScene
├── TimerManager (Node)
│   ├── CanvasLayer
│   │   ├── TimerLabel (Label)
│   │   └── TimerButton (Button)
│   └── InternalTimer (Timer)
```

### Step 2: Attach the Script

1. Select the `TimerManager` node
2. Attach `timer_manager.gd` script to it
3. The script will automatically find and configure the UI elements

### Step 3: Configure UI Appearance (Optional)

**For TimerLabel:**
- Adjust position using anchor_left, anchor_top, offset_left, offset_top
- Example (top-center, 48px font):
  ```
  anchor_left = 0.5
  anchor_top = 0.05
  offset_left = -120  # Width/2
  offset_right = 120
  ```

**For TimerButton:**
- Adjust position below the label
- Example (below label, 24px font):
  ```
  anchor_left = 0.5
  anchor_top = 0.15
  offset_left = -60   # Width/2
  offset_right = 60
  text = "Start"
  ```

## API Reference

### Methods

```gdscript
# Control the timer
timer_manager.start_timer()      # Start counting
timer_manager.stop_timer()       # Pause counting
timer_manager.reset_timer()      # Reset to 00:00:00

# Get timer information
var elapsed = timer_manager.get_elapsed_time()    # Returns seconds as float
var time_str = timer_manager.get_time_string()    # Returns "HH:MM:SS"
var running = timer_manager.is_timer_running()    # Returns bool

# Internal formatting
var formatted = timer_manager.format_time(125.5)  # Returns "00:02:05"
```

## Usage Examples

### Example 1: Start timer on button press (from another script)

```gdscript
extends Node

@onready var timer_manager = get_node("TimerManager")

func _on_start_game_button_pressed():
    timer_manager.start_timer()
    print("Game started!")

func _on_end_game_button_pressed():
    timer_manager.stop_timer()
    var final_time = timer_manager.get_time_string()
    print("Game ended! Time: " + final_time)
```

### Example 2: Display timer in game UI

```gdscript
extends Label

@onready var timer_manager = get_node("../TimerManager")

func _process(_delta):
    text = "Elapsed: " + timer_manager.get_time_string()
```

### Example 3: Auto-reset timer when scene loads

```gdscript
func _ready():
    var timer = get_node("TimerManager")
    timer.reset_timer()
    timer.start_timer()
```

## Auto-Creation Behavior

If you don't create the required child nodes, `timer_manager.gd` will **automatically create them**:

- ✅ No `TimerLabel` → Creates default Label at top-center
- ✅ No `TimerButton` → Creates default Button below label
- ✅ No `InternalTimer` → Creates internal Timer node

**Note:** The script uses `find_child()` to locate nodes, so names must match exactly:
- Label node must be named: `TimerLabel`
- Button node must be named: `TimerButton`
- Timer node must be named: `InternalTimer`

## Styling the Timer

### Change Font Size

```gdscript
# In your scene's _ready():
timer_label.add_theme_font_size_override("font_size", 64)  # Larger
```

### Change Colors

```gdscript
# White text (default)
timer_label.add_theme_color_override("font_color", Color.WHITE)

# Custom color (RGB)
timer_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))

# Hex color
timer_label.add_theme_color_override("font_color", Color("#00FF00"))
```

### Change Button Appearance

```gdscript
# Button text color
timer_button.add_theme_color_override("font_color", Color.BLACK)

# Button background (using StyleBox)
var style = StyleBoxFlat.new()
style.bg_color = Color.BLUE
timer_button.add_theme_stylebox_override("normal", style)
```

## Console Output

The timer prints messages to help with debugging:

```
⏱️ Timer Manager initialized
✅ Found TimerLabel
✅ Found TimerButton
✅ Found InternalTimer
⏱️ Timer started
⏱️ Timer stopped at 00:00:45
⏱️ Timer reset
```

## Position Reference

- **anchor_left = 0.5, anchor_top = 0.05** → Top-center, 5% from top
- **anchor_left = 0.0, anchor_top = 0.0** → Top-left
- **anchor_left = 1.0, anchor_top = 1.0** → Bottom-right

Adjust `offset_left/right/top/bottom` for fine positioning.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Timer not visible | Check `CanvasLayer` is a child and layer is high (e.g., 100) |
| Button not responding | Verify button node is named exactly `TimerButton` |
| Label not updating | Check `TimerLabel` child node exists and is visible |
| Timer counting wrong | Verify `InternalTimer.wait_time = 0.1` (100ms ticks) |

## Integration with BoardSetup

To add the timer to the existing `board_setup.tscn`:

1. Open `board_setup.tscn` in Godot editor
2. Add a new Node as a child of the root
3. Name it `TimerManager`
4. Attach `timer_manager.gd` script
5. Save and run!

The timer will work alongside your 3D visualization.

---

**Created:** 2025-12-23
**Version:** 1.0
**Status:** Ready for use
