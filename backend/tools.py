# tools.py - Vehicle Simulator State and Control Functions

import json
import os

# Define the state file path
STATE_FILE = os.path.join(os.path.dirname(__file__), "..", "data", "vehicle_state.json")
PROFILE_FILE = os.path.join(os.path.dirname(__file__), "..", "data", "user_profile.json")

# Ensure the data directory exists
os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)

# Default vehicle simulator state
DEFAULT_STATE = {
    "ac_temp": 22.0,
    "fan_speed": 3,
    "windows_open": False,
    "doors_locked": True,
    "hazard_lights": False,
    "headlights": "Auto",
    "wipers": "Off",
    "drive_mode": "Comfort", # Eco, Comfort, Sport
    "music_playing": False,
    "music_track": "None",
    "music_playlist": "None",
    "current_route": "None",
    "fuel_level": 15, # percentage (low fuel warning at <= 15)
    "battery_level": 45, # percentage
    "tpms_status": "Normal", # or "Warning", "Malfunction"
    "tire_pressures": {"FL": 34, "FR": 34, "RL": 32, "RR": 32},
    "speed": 0,
    "is_rainy": False,
    "driver_fatigue_hours": 0.0,
    "driver_mood": "Normal", # Normal, Stressed, Sleepy, Energetic
    "current_profile": "Dad", # Dad, Mom, Child
}

# Default profiles
DEFAULT_PROFILES = {
    "Dad": {
        "preferred_temp": 21.0,
        "drive_mode": "Sport",
        "favorite_music": "A.R. Rahman Hits",
        "avoid_tolls": True,
        "commute_time": "08:30 AM to Office",
        "seat_position": "Memory 1",
        "driving_habits": "Prefers dynamic sporty driving, stops for tea after 150 km"
    },
    "Mom": {
        "preferred_temp": 23.0,
        "drive_mode": "Comfort",
        "favorite_music": "Acoustic Pop",
        "avoid_tolls": False,
        "commute_time": "09:00 AM to Design Studio",
        "seat_position": "Memory 2",
        "driving_habits": "Prefers smooth eco driving, avoids highways when rainy"
    },
    "Child": {
        "preferred_temp": 22.0,
        "drive_mode": "Eco",
        "favorite_music": "Disney Hits",
        "avoid_tolls": False,
        "commute_time": "None",
        "seat_position": "Rear Right",
        "driving_habits": "Requires child lock active, enjoys rear seat entertainment"
    }
}

def load_state():
    try:
        if os.path.exists(STATE_FILE):
            with open(STATE_FILE, "r") as f:
                return json.load(f)
    except Exception as e:
        print(f"Error loading state: {e}")
    # Save default if not exists
    save_state(DEFAULT_STATE)
    return DEFAULT_STATE.copy()

def save_state(state):
    try:
        with open(STATE_FILE, "w") as f:
            json.dump(state, f, indent=4)
    except Exception as e:
        print(f"Error saving state: {e}")

def load_profiles():
    try:
        if os.path.exists(PROFILE_FILE):
            with open(PROFILE_FILE, "r") as f:
                return json.load(f)
    except Exception as e:
        print(f"Error loading profiles: {e}")
    # Save default if not exists
    save_profiles(DEFAULT_PROFILES)
    return DEFAULT_PROFILES.copy()

def save_profiles(profiles):
    try:
        with open(PROFILE_FILE, "w") as f:
            json.dump(profiles, f, indent=4)
    except Exception as e:
        print(f"Error saving profiles: {e}")

# Tool Functions that manipulate State

def set_ac_temp(temp: float):
    state = load_state()
    state["ac_temp"] = round(float(temp), 1)
    save_state(state)
    return f"AC temperature set to {state['ac_temp']}°C."

def adjust_ac(direction: str):
    # direction can be "colder", "warmer"
    state = load_state()
    if direction == "colder":
        state["ac_temp"] = max(16.0, state["ac_temp"] - 1.0)
    elif direction == "warmer":
        state["ac_temp"] = min(30.0, state["ac_temp"] + 1.0)
    save_state(state)
    return f"AC adjusted. Temperature is now {state['ac_temp']}°C."

def set_windows(open_win: bool):
    state = load_state()
    state["windows_open"] = bool(open_win)
    save_state(state)
    return "Windows opened." if state["windows_open"] else "Windows closed."

def set_doors_locked(locked: bool):
    state = load_state()
    state["doors_locked"] = bool(locked)
    save_state(state)
    return "Doors locked." if state["doors_locked"] else "Doors unlocked."

def set_hazard_lights(active: bool):
    state = load_state()
    state["hazard_lights"] = bool(active)
    save_state(state)
    return "Hazard lights activated." if state["hazard_lights"] else "Hazard lights deactivated."

def set_drive_mode(mode: str):
    state = load_state()
    valid_modes = ["Eco", "Comfort", "Sport"]
    matched_mode = next((m for m in valid_modes if m.lower() == mode.lower()), "Comfort")
    state["drive_mode"] = matched_mode
    save_state(state)
    return f"Drive mode changed to {matched_mode}."

def play_music(playlist: str = None, track: str = None):
    state = load_state()
    state["music_playing"] = True
    if playlist:
        state["music_playlist"] = playlist
        state["music_track"] = f"{playlist} Playlist (Playing...)"
    elif track:
        state["music_track"] = track
        state["music_playlist"] = "Custom Selection"
    else:
        state["music_track"] = "Driver's Favorites"
        state["music_playlist"] = "Favorites"
    save_state(state)
    return f"Music started: Playing {state['music_track']}."

def stop_music():
    state = load_state()
    state["music_playing"] = False
    state["music_track"] = "None"
    state["music_playlist"] = "None"
    save_state(state)
    return "Music stopped."

def start_navigation(destination: str):
    state = load_state()
    state["current_route"] = destination
    # Simulate a smart route selection based on profiles or standard logic
    avoid_tolls_msg = " (Avoiding tolls)" if state["current_profile"] == "Dad" else ""
    save_state(state)
    return f"Navigation started to {destination}{avoid_tolls_msg}."

def activate_emergency_mode():
    state = load_state()
    state["hazard_lights"] = True
    state["doors_locked"] = False # Unlocked for emergency services
    save_state(state)
    
    profile = state["current_profile"]
    contact = "911 / Emergency Services"
    medical_info = "No specific medical history on file."
    
    if profile == "Dad":
        contact = "Wife (Mom) - +1 (555) 019-2834"
        medical_info = "Blood Group: O+, Penicillin Allergy"
    elif profile == "Mom":
        contact = "Husband (Dad) - +1 (555) 019-4821"
        medical_info = "Blood Group: A+, No allergies"
        
    response = {
        "hazard_lights": "Activated",
        "doors_unlocked": "True (for emergency access)",
        "emergency_call_initiated_to": contact,
        "gps_coordinates_shared": "Latitude: 19.0760° N, Longitude: 72.8777° E (Mumbai)",
        "medical_info_dispatched": medical_info
    }
    return json.dumps(response)

def switch_profile(profile_name: str):
    state = load_state()
    profiles = load_profiles()
    if profile_name in profiles:
        state["current_profile"] = profile_name
        # Apply preferences
        pref = profiles[profile_name]
        state["ac_temp"] = pref["preferred_temp"]
        state["drive_mode"] = pref["drive_mode"]
        # Save state
        save_state(state)
        return f"Switched to {profile_name}'s profile. Seating set to {pref['seat_position']}. AC set to {pref['preferred_temp']}°C. Drive mode set to {pref['drive_mode']}."
    return f"Profile '{profile_name}' not found."

def set_sensor_state(key: str, value):
    # This is for the simulator to trigger rain, low fuel, low battery, sleepiness
    state = load_state()
    if key in state:
        state[key] = value
        save_state(state)
        return f"Vehicle sensor '{key}' updated to {value}."
    return f"Unknown sensor '{key}'."

# Map command strings to functions
def execute_vehicle_command(command_str: str) -> str:
    """
    Parses a command like 'set_ac_temp(21.5)' or 'open_windows()' and executes it.
    """
    try:
        command_str = command_str.strip()
        if not command_str:
            return "Empty command"
        
        # Simple parsing: find name and arguments
        if "(" in command_str and command_str.endswith(")"):
            name = command_str.split("(")[0].strip()
            args_str = command_str.split("(")[1][:-1].strip()
            
            # Parse arguments
            args = []
            kwargs = {}
            if args_str:
                # split by comma, but be careful with quotes
                parts = args_str.split(",")
                for part in parts:
                    part = part.strip()
                    if "=" in part:
                        k, v = part.split("=")
                        k = k.strip()
                        v = v.strip().strip("'").strip('"')
                        # Try to cast
                        if v.lower() == "true":
                            kwargs[k] = True
                        elif v.lower() == "false":
                            kwargs[k] = False
                        else:
                            try:
                                if "." in v:
                                    kwargs[k] = float(v)
                                else:
                                    kwargs[k] = int(v)
                            except ValueError:
                                kwargs[k] = v
                    else:
                        v = part.strip().strip("'").strip('"')
                        if v.lower() == "true":
                            args.append(True)
                        elif v.lower() == "false":
                            args.append(False)
                        else:
                            try:
                                if "." in v:
                                    args.append(float(v))
                                else:
                                    args.append(int(v))
                            except ValueError:
                                args.append(v)
            
            # Execute
            if name == "set_ac_temp":
                return set_ac_temp(*args, **kwargs)
            elif name == "adjust_ac":
                return adjust_ac(*args, **kwargs)
            elif name == "set_windows":
                return set_windows(*args, **kwargs)
            elif name == "set_doors_locked":
                return set_doors_locked(*args, **kwargs)
            elif name == "set_hazard_lights":
                return set_hazard_lights(*args, **kwargs)
            elif name == "set_drive_mode":
                return set_drive_mode(*args, **kwargs)
            elif name == "play_music":
                return play_music(*args, **kwargs)
            elif name == "stop_music":
                return stop_music(*args, **kwargs)
            elif name == "start_navigation":
                return start_navigation(*args, **kwargs)
            elif name == "activate_emergency_mode":
                return activate_emergency_mode()
            elif name == "switch_profile":
                return switch_profile(*args, **kwargs)
            elif name == "set_sensor_state":
                return set_sensor_state(*args, **kwargs)
            else:
                return f"Error: Unknown command function '{name}'"
        else:
            return f"Error: Invalid command format '{command_str}'"
    except Exception as e:
        return f"Error executing command: {e}"
