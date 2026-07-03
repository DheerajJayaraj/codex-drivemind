# whisper_engine.py - Speech-to-Text & Text-to-Speech fallbacks

import os
import sys

# Standard python speech synthesis fallback (using native win32 COM if on Windows, or mock if elsewhere)
_tts_engine = None

def init_tts():
    global _tts_engine
    if _tts_engine is not None:
        return _tts_engine
        
    try:
        # Check if pyttsx3 is installed
        import pyttsx3
        _tts_engine = pyttsx3.init()
        # Set default properties
        _tts_engine.setProperty('rate', 160)     # Speed
        _tts_engine.setProperty('volume', 1.0)   # Volume (0.0 to 1.0)
        return _tts_engine
    except ImportError:
        # Fallback to win32com speech on Windows directly (zero dependencies)
        if sys.platform == 'win32':
            try:
                import win32com.client
                _tts_engine = win32com.client.Dispatch("SAPI.SpVoice")
                return _tts_engine
            except Exception as e:
                print(f"SAPI voice initialization failed: {e}")
        print("TTS Engine: Python offline TTS package 'pyttsx3' not installed. Fallback to text responses.")
        return None

def transcribe_audio(audio_file_path: str) -> str:
    """
    Transcribes audio file to text.
    In a full production environment, this uses faster-whisper.
    For this Edge AI MVP, if faster-whisper is not installed,
    we can use a lightweight python speech recognition engine, or return a mock.
    """
    print(f"Transcribing audio: {audio_file_path}")
    try:
        # Check if SpeechRecognition is installed
        import speech_recognition as sr
        r = sr.Recognizer()
        with sr.AudioFile(audio_file_path) as source:
            audio_data = r.record(source)
            text = r.recognize_google(audio_data) # Note: needs internet. For offline, Sphinx can be used.
            return text
    except Exception as e:
        print(f"Speech recognition fallback error: {e}")
        
    # Standard demo fallback
    return "Hello"

def speak_text_offline(text: str):
    """
    Speaks text offline using the system voice.
    """
    print(f"Speaking: {text}")
    engine = init_tts()
    if engine is None:
        return False
        
    try:
        # Check if pyttsx3 was loaded
        if hasattr(engine, 'say'):
            engine.say(text)
            engine.runAndWait()
            return True
        # Check if SAPI was loaded
        elif hasattr(engine, 'Speak'):
            engine.Speak(text)
            return True
    except Exception as e:
        print(f"Error speaking text: {e}")
    return False
