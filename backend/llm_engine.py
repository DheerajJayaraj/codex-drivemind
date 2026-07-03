# llm_engine.py - Local Ollama connection & System Prompts

import json
from langchain_ollama import ChatOllama
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.messages import HumanMessage, SystemMessage, AIMessage
from backend.tools import load_state, load_profiles, execute_vehicle_command
from backend.rag_pipeline import retrieve_manual_context

# Initialize ChatOllama with local model
# We use phi3:mini as it is installed and verified.
llm = ChatOllama(model="phi3:mini", temperature=0.1)

# System Prompt Template
SYSTEM_PROMPT_TEMPLATE = """You are "DriveMind", the next-generation AI operating system and intelligent co-driver for a Tata Nexon EV.
You run completely locally (Edge AI) to ensure maximum privacy, low latency, and offline reliability.

You are an empathetic, alert, and intelligent driving assistant, travel planner, emergency assistant, car expert, and energy optimizer all in one.
Your response MUST be conversational, helpful, and concise.

CURRENT VEHICLE STATE:
{vehicle_state_json}

ACTIVE PROFILE INFO ({current_profile}):
{profile_json}

MANUAL CONTEXT (RAG):
{manual_context}

CRITICAL RULES FOR RESPONDING:
1. Ground your technical answers in the provided MANUAL CONTEXT. If the TPMS, Tortoise mode, or fuse box is mentioned, look at the MANUAL CONTEXT.
2. If you want to trigger a vehicle action, you MUST append the exact command at the END of your reply using this format:
   `[VEHICLE_ACTION: <command>]`
   Available commands:
   - `set_ac_temp(temp=X)`  (e.g., set_ac_temp(temp=21.0))
   - `adjust_ac(direction='colder'|'warmer')`
   - `set_windows(open_win=True|False)`
   - `set_doors_locked(locked=True|False)`
   - `set_hazard_lights(active=True|False)`
   - `set_drive_mode(mode='Eco'|'Comfort'|'Sport')`
   - `play_music(playlist='evening'|'favorites'|'soft', track='optional')`
   - `stop_music()`
   - `start_navigation(destination='destination name')`
   - `activate_emergency_mode()`
   - `switch_profile(profile_name='Dad'|'Mom'|'Child')`
   You can append MULTIPLE actions if necessary (one per line).

3. PREDICTIVE SUGGESTIONS & SCENARIOS:
   - If the driver says "I'm sleepy" or "I'm tired": notice that their fatigue is high. Suggest a coffee shop nearby (e.g. "Starbucks is 4 km away") and ask if they want to navigate there.
   - If the fuel/battery level is low: suggest the nearest charging/petrol station and offer navigation.
   - If it starts raining: suggest turning on headlights/wipers.
   - If the user is stressed: lower the AC temperature slightly, start playing soft music, and suggest a relaxing route. E.g. `[VEHICLE_ACTION: set_ac_temp(temp=20.0)]` and `[VEHICLE_ACTION: play_music(playlist='soft')]`.
   - If the user says they had an accident: immediately trigger emergency mode. This will turn on hazards, unlock doors, dial emergency contact, and display medical info. E.g. `[VEHICLE_ACTION: activate_emergency_mode()]`.

4. EXPLAINABILITY:
   - When suggesting a route or changes, briefly explain why (e.g., "I've routed you through Eastern Freeway to avoid 15 minutes of traffic on LBS Road").
   - When asked what you know about the driver, explain their preferences (preferred AC temp, music genre, driving style, commute timing, seat position) retrieved from their profile.

Answer the driver's request now:
"""

def generate_co_pilot_response(user_message: str, chat_history: list = None) -> dict:
    """
    Invokes the LLM with the latest state, profile, and manual context.
    Returns:
        dict: {
            "reply": str,
            "actions": list of command strings,
            "executed_results": list of execution confirmations
        }
    """
    if chat_history is None:
        chat_history = []
        
    # 1. Load active state and profiles
    state = load_state()
    profiles = load_profiles()
    current_profile = state.get("current_profile", "Dad")
    profile_info = profiles.get(current_profile, {})
    
    # 2. RAG Retrieval if relevant
    # Check if query is related to manual, warnings, lights, fuses, tire pressure, or battery
    manual_context = ""
    query_keywords = ["tpms", "tire", "pressure", "light", "warning", "fuse", "battery", "tortoise", "charging", "nexon", "manual", "maintenance"]
    if any(kw in user_message.lower() for kw in query_keywords):
        print(f"RAG: Retrieving context for query: {user_message}")
        manual_context = retrieve_manual_context(user_message)
        if not manual_context:
            manual_context = "No direct documentation retrieved. Fallback to general vehicle safety guidelines."
    else:
        manual_context = "No direct manual query detected. Keep focus on general passenger assistance."
        
    # 3. Format system prompt
    system_prompt = SYSTEM_PROMPT_TEMPLATE.format(
        vehicle_state_json=json.dumps(state, indent=2),
        current_profile=current_profile,
        profile_json=json.dumps(profile_info, indent=2),
        manual_context=manual_context
    )
    
    # 4. Construct message list for LangChain
    messages = [SystemMessage(content=system_prompt)]
    
    # Append recent chat history
    for msg in chat_history[-6:]: # Limit history to last 6 messages
        if msg.get("role") == "user":
            messages.append(HumanMessage(content=msg.get("content", "")))
        elif msg.get("role") == "assistant":
            messages.append(AIMessage(content=msg.get("content", "")))
            
    messages.append(HumanMessage(content=user_message))
    
    # 5. Invoke LLM
    print("Calling Ollama (Phi-3 Mini)...")
    try:
        response = llm.invoke(messages)
        raw_reply = response.content
    except Exception as e:
        print(f"Ollama execution error: {e}")
        raw_reply = "I'm having trouble connecting to my local processor right now. However, I can still assist with manual safety protocols. What can I do for you?"
        
    # 6. Parse actions from response
    clean_reply = []
    actions = []
    
    for line in raw_reply.split("\n"):
        if "[VEHICLE_ACTION:" in line:
            start_idx = line.find("[VEHICLE_ACTION:") + len("[VEHICLE_ACTION:")
            end_idx = line.find("]", start_idx)
            if end_idx != -1:
                action_cmd = line[start_idx:end_idx].strip()
                actions.append(action_cmd)
                # Strip action bracket from user-visible reply
                line = line[:line.find("[VEHICLE_ACTION:")].strip()
        if line.strip():
            clean_reply.append(line)
            
    reply_text = "\n".join(clean_reply)
    
    # 7. Execute parsed actions and update vehicle state
    executed_results = []
    for action in actions:
        print(f"Executing vehicle action: {action}")
        res = execute_vehicle_command(action)
        executed_results.append(res)
        
    return {
        "reply": reply_text,
        "actions": actions,
        "executed_results": executed_results
    }
