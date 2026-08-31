import chromadb

client = chromadb.PersistentClient(path="./chroma_db")
collection = client.get_or_create_collection(name="survival_manuals")

# Official protocols adapted from NDMA, FEMA, and Red Cross
documents = [
    "EVACUATION PROTOCOL: If water reaches knee level (0.5m) or an official evacuation order is given, evacuate immediately. Do not wait for water levels to rise further.",
    "WALKING IN FLOODWATER: Never walk, swim, or drive through swift-flowing water. Just 15 cm (6 inches) of moving water can knock you down, and 30 cm (1 foot) can sweep a vehicle away. Turn Around, Don't Drown.",
    "SHELTER IN PLACE: If trapped in a building, move to the highest level. Do not climb into a closed attic where you may become trapped by rising water. Only go to the roof if necessary, and signal for help.",
    "ELECTRICAL SAFETY: Turn off main power switches and unplug appliances if water enters your premises. Never touch electrical equipment, switches, or cords while you are wet or standing in water.",
    "DRINKING WATER AND SANITATION: Assume all tap water is contaminated. Boil water for at least 1 minute or use purification tablets before drinking or cooking. Floodwaters carry heavy bacterial loads and raw sewage.",
    "WILDLIFE AND HAZARDS: Be highly cautious of snakes, insects, and stray animals that may have sought shelter in your home during the flood. Use a stick to poke through debris rather than your hands.",
    "MEDICAL EMERGENCIES: Wash all cuts or open wounds immediately with soap and clean water to prevent infection from floodwater. Apply antibiotic ointment and a waterproof bandage.",
    "POST-FLOOD RE-ENTRY: Do not return to your home until officials have declared it safe. Check for structural damage before entering, and use flashlights instead of candles or matches in case of gas leaks.",
    "EMERGENCY KIT PREPARATION: A basic flood survival kit must include a 3-day supply of bottled water, non-perishable food, a first-aid kit, a flashlight, spare batteries, and essential medications.",
    "COMMUNICATION PROTOCOL: Keep phone lines clear for emergencies. Use SMS text messaging instead of voice calls to communicate with family, as text messages use less network bandwidth and are more likely to go through."
]

# Create unique IDs for each doc
ids = [f"doc_{i}" for i in range(len(documents))]

# Add them to the local Vector Database
collection.add(documents=documents, ids=ids)
print(f"✅ Successfully seeded {len(documents)} official emergency protocols into ChromaDB RAG system.")