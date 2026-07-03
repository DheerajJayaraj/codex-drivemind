# rag_pipeline.py - ChromaDB setup and retrieval

import os
from pydantic import BaseModel
from langchain_chroma import Chroma
from langchain_ollama import OllamaEmbeddings
from langchain_text_splitters import RecursiveCharacterTextSplitter
import pypdf

# Paths
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PDF_PATH = os.path.join(BASE_DIR, "tata_nexon.pdf")
TXT_PATH = os.path.join(BASE_DIR, "car_manual.txt")
DB_DIR = os.path.join(BASE_DIR, "data", "chroma_db")

# Initialize Local Embeddings via Ollama
embeddings = OllamaEmbeddings(model="nomic-embed-text")

_retriever = None

def get_retriever():
    global _retriever
    if _retriever is not None:
        return _retriever
        
    # Check if vector db already exists
    if os.path.exists(DB_DIR) and len(os.listdir(DB_DIR)) > 0:
        print("Loading existing Chroma vector database from disk...")
        vector_store = Chroma(persist_directory=DB_DIR, embedding_function=embeddings)
        _retriever = vector_store.as_retriever(search_kwargs={"k": 3})
        return _retriever
        
    # Database does not exist, we need to build it
    print("Building Chroma vector database...")
    documents = []
    
    # 1. Try to read from PDF manual
    if os.path.exists(PDF_PATH):
        print(f"Extracting text from PDF manual: {PDF_PATH}...")
        try:
            reader = pypdf.PdfReader(PDF_PATH)
            # Limit page count for faster build if needed, but Nexon manual is usually around 200-300 pages.
            # Let's extract all, but print progress.
            total_pages = len(reader.pages)
            print(f"Total pages to extract: {total_pages}")
            
            for i, page in enumerate(reader.pages):
                text = page.extract_text()
                if text and len(text.strip()) > 50:
                    # Keep track of page source
                    documents.append({
                        "text": text,
                        "metadata": {"source": "tata_nexon.pdf", "page": i + 1}
                    })
        except Exception as e:
            print(f"Error parsing PDF: {e}. Falling back to text guide...")
            
    # 2. Try to read from text manual as fallback or supplementary
    if os.path.exists(TXT_PATH):
        print(f"Reading quick reference text guide: {TXT_PATH}...")
        try:
            with open(TXT_PATH, "r", encoding="utf-8") as f:
                text = f.read()
                documents.append({
                    "text": text,
                    "metadata": {"source": "car_manual.txt", "page": 1}
                })
        except Exception as e:
            print(f"Error reading text guide: {e}")
            
    if not documents:
        # Create a basic quick-start manual if absolutely nothing is found
        print("No manuals found. Creating default manual text...")
        default_manual = """
        TATA NEXON EV (2026) - QUICK REFERENCE
        SECTION 1: TPMS System
        Tire Pressure Warning Light: Illuminates yellow. Cold pressure: Front 34 PSI, Rear 32 PSI.
        Flashing for 1 minute then solid indicates system malfunction.
        
        SECTION 2: Battery Warnings
        Tortoise Mode: Yellow turtle icon. Critically low battery. Speed capped at 40 km/h.
        Glow Plug / Pre-heating: Battery pre-heating system active.
        
        SECTION 3: Fuse Box Locations
        Cabin Fuse Box: Under steering column, near driver right knee.
        Engine Fuse Box: In engine bay, adjacent to 12V battery.
        """
        documents.append({
            "text": default_manual,
            "metadata": {"source": "default_fallback", "page": 1}
        })
        
    # Split text into chunks
    text_splitter = RecursiveCharacterTextSplitter(chunk_size=400, chunk_overlap=80)
    split_docs = []
    
    for doc in documents:
        chunks = text_splitter.split_text(doc["text"])
        for chunk in chunks:
            # We create a LangChain Document structure using simple dictionary mapping
            # or directly using Document class from langchain_core
            from langchain_core.documents import Document
            split_docs.append(Document(page_content=chunk, metadata=doc["metadata"]))
            
    print(f"Created {len(split_docs)} text chunks. Vectorizing & saving to Chroma DB...")
    
    # Store in Chroma DB
    vector_store = Chroma.from_documents(split_docs, embeddings, persist_directory=DB_DIR)
    
    _retriever = vector_store.as_retriever(search_kwargs={"k": 3})
    print("Vector database built successfully!")
    return _retriever

def retrieve_manual_context(query: str) -> str:
    try:
        retriever = get_retriever()
        docs = retriever.invoke(query)
        context_parts = []
        for i, doc in enumerate(docs):
            src = doc.metadata.get("source", "manual")
            pg = doc.metadata.get("page", 1)
            context_parts.append(f"[{src} Page {pg}]: {doc.page_content}")
        return "\n\n".join(context_parts)
    except Exception as e:
        print(f"RAG retrieval error: {e}")
        return "No manual context retrieved due to an error."
