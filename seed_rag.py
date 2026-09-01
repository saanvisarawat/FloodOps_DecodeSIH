import os
import chromadb

# Connect to your local Vector DB
client = chromadb.PersistentClient(path="./chroma_db")
collection = client.get_or_create_collection(name="survival_manuals")

folder_path = "./manuals"

# Ensure the folder exists
if not os.path.exists(folder_path):
    os.makedirs(folder_path)
    print(f"⚠️ Created a folder named '{folder_path}'. Please drop your detailed .txt files inside it and run this again.")
    exit()

all_documents = []
all_ids = []
doc_counter = 0

# Loop through every text file in the folder
for filename in os.listdir(folder_path):
    if filename.endswith(".txt"):
        filepath = os.path.join(folder_path, filename)
        
        # Read the file
        with open(filepath, "r", encoding="utf-8", errors="ignore") as file:
            content = file.read()
            
            # "Chunking": Split the massive document by double-newlines (paragraphs)
            paragraphs = content.split('\n\n')
            
            for para in paragraphs:
                clean_para = para.strip()
                
                # Only keep chunks that actually have detailed info (ignore short titles/empty lines)
                if len(clean_para) > 100: 
                    all_documents.append(clean_para)
                    all_ids.append(f"doc_{doc_counter}")
                    doc_counter += 1

if len(all_documents) == 0:
    print("⚠️ No valid text found. Make sure your .txt files have content.")
else:
    # Add all chunks into ChromaDB at once
    collection.add(documents=all_documents, ids=all_ids)
    print(f"✅ BOOM! Successfully injected {len(all_documents)} detailed knowledge chunks into your RAG system.")