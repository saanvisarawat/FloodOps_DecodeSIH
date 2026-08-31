import os
from langchain_chroma import Chroma
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_core.documents import Document

# Initialize local embedding model (runs completely offline on CPU)
embeddings = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")

survival_knowledge = [
    Document(
        page_content="Electrical and Utilities Safety in Rising Water:\n"
                     "- Never touch electrical equipment, switches, or appliances if you are wet or standing in water.\n"
                     "- Turn off the main circuit breaker or fuse box if you can reach it safely without stepping into flooded areas.\n"
                     "- Disconnect appliances and elevate portable electronics to high shelves, countertops, or upper floors.\n"
                     "- If water begins entering rooms where outlets or wiring are submerged, evacuate immediately to higher ground.",
        metadata={"category": "electrical_safety", "source": "FloodOps Protocol v1"}
    ),
    Document(
        page_content="Immediate Evacuation and High Ground Protocol:\n"
                     "- When waters exceed knee depth (approx. 0.5m), do not attempt to walk or wade through flowing water.\n"
                     "- Gather essential survival items: identification, medicines, emergency lights, and water disinfection tablets.\n"
                     "- Move vertically to an upper floor, reinforced roof terrace, or nearest elevated shelter immediately.\n"
                     "- Signal for rescue using a whistle, reflective surface, or brightly colored cloth. Do not climb into enclosed attics without roof exits.",
        metadata={"category": "evacuation", "source": "FloodOps Protocol v1"}
    )
]

print("Indexing emergency survival manuals into ChromaDB...")
vector_store = Chroma(
    collection_name="survival_manuals",
    embedding_function=embeddings,
    persist_directory="./chroma_db"
)
vector_store.add_documents(survival_knowledge)
print("Seeding complete. Survival manual context is now queryable completely offline.")