import httpx
from bs4 import BeautifulSoup

kerala_live_cache = {
    "last_updated": None,
    "districts": {},
    "reservoirs": []
}

KERALA_DISTRICTS = {
    "Thiruvananthapuram": {"lat": 8.52, "lon": 76.93},
    "Kollam": {"lat": 8.89, "lon": 76.61},
    "Pathanamthitta": {"lat": 9.26, "lon": 76.78},
    "Alappuzha": {"lat": 9.49, "lon": 76.33},
    "Kottayam": {"lat": 9.59, "lon": 76.52},
    "Idukki": {"lat": 9.85, "lon": 76.94},
    "Ernakulam": {"lat": 9.98, "lon": 76.28},
    "Thrissur": {"lat": 10.52, "lon": 76.21},
    "Palakkad": {"lat": 10.78, "lon": 76.65},
    "Malappuram": {"lat": 11.07, "lon": 76.07},
    "Kozhikode": {"lat": 11.25, "lon": 75.78},
    "Wayanad": {"lat": 11.68, "lon": 76.13},
    "Kannur": {"lat": 11.87, "lon": 75.37},
    "Kasaragod": {"lat": 12.49, "lon": 74.98}
}

async def fetch_open_meteo_data():
    """
    Fetches real-time weather & discharge data from Open-Meteo, 
    or supplies an active monsoon demo state when enabled.
    """
    DEMO_MONSOON_MODE = False  # Set to False to hit live Open-Meteo API endpoints

    if DEMO_MONSOON_MODE:
        return {
            "Alappuzha": {
                "rainfall_mm": 115.0, "rainfall_mm_3d_sum": 310.0, "rainfall_mm_7d_sum": 580.0, "rainfall_mm_15d_sum": 790.0,
                "river_discharge": 780.0, "river_discharge_m3s": 780.0, "river_discharge_3d_sum": 2100.0, "river_discharge_7d_sum": 4500.0, "river_discharge_15d_sum": 7800.0
            },
            "Ernakulam": {
                "rainfall_mm": 130.0, "rainfall_mm_3d_sum": 340.0, "rainfall_mm_7d_sum": 620.0, "rainfall_mm_15d_sum": 840.0,
                "river_discharge": 890.0, "river_discharge_m3s": 890.0, "river_discharge_3d_sum": 2400.0, "river_discharge_7d_sum": 5100.0, "river_discharge_15d_sum": 8800.0
            },
            "Kottayam": {
                "rainfall_mm": 105.0, "rainfall_mm_3d_sum": 280.0, "rainfall_mm_7d_sum": 520.0, "rainfall_mm_15d_sum": 710.0,
                "river_discharge": 650.0, "river_discharge_m3s": 650.0, "river_discharge_3d_sum": 1800.0, "river_discharge_7d_sum": 3900.0, "river_discharge_15d_sum": 6700.0
            },
            "Idukki": {
                "rainfall_mm": 95.0, "rainfall_mm_3d_sum": 250.0, "rainfall_mm_7d_sum": 480.0, "rainfall_mm_15d_sum": 650.0,
                "river_discharge": 420.0, "river_discharge_m3s": 420.0, "river_discharge_3d_sum": 1200.0, "river_discharge_7d_sum": 2600.0, "river_discharge_15d_sum": 4600.0
            },
            "Wayanad": {
                "rainfall_mm": 88.0, "rainfall_mm_3d_sum": 230.0, "rainfall_mm_7d_sum": 440.0, "rainfall_mm_15d_sum": 610.0,
                "river_discharge": 380.0, "river_discharge_m3s": 380.0, "river_discharge_3d_sum": 1050.0, "river_discharge_7d_sum": 2300.0, "river_discharge_15d_sum": 4100.0
            },
            "Thrissur": {
                "rainfall_mm": 70.0, "rainfall_mm_3d_sum": 180.0, "rainfall_mm_7d_sum": 360.0, "rainfall_mm_15d_sum": 510.0,
                "river_discharge": 210.0, "river_discharge_m3s": 210.0, "river_discharge_3d_sum": 600.0, "river_discharge_7d_sum": 1300.0, "river_discharge_15d_sum": 2400.0
            },
            "Pathanamthitta": {
                "rainfall_mm": 60.0, "rainfall_mm_3d_sum": 160.0, "rainfall_mm_7d_sum": 320.0, "rainfall_mm_15d_sum": 460.0,
                "river_discharge": 190.0, "river_discharge_m3s": 190.0, "river_discharge_3d_sum": 520.0, "river_discharge_7d_sum": 1150.0, "river_discharge_15d_sum": 2100.0
            },
            "Malappuram": {
                "rainfall_mm": 40.0, "rainfall_mm_3d_sum": 110.0, "rainfall_mm_7d_sum": 220.0, "rainfall_mm_15d_sum": 340.0,
                "river_discharge": 80.0, "river_discharge_m3s": 80.0, "river_discharge_3d_sum": 230.0, "river_discharge_7d_sum": 510.0, "river_discharge_15d_sum": 980.0
            },
            "Kozhikode": {
                "rainfall_mm": 35.0, "rainfall_mm_3d_sum": 95.0, "rainfall_mm_7d_sum": 190.0, "rainfall_mm_15d_sum": 300.0,
                "river_discharge": 60.0, "river_discharge_m3s": 60.0, "river_discharge_3d_sum": 170.0, "river_discharge_7d_sum": 380.0, "river_discharge_15d_sum": 750.0
            },
            "Kannur": {
                "rainfall_mm": 25.0, "rainfall_mm_3d_sum": 70.0, "rainfall_mm_7d_sum": 140.0, "rainfall_mm_15d_sum": 220.0,
                "river_discharge": 45.0, "river_discharge_m3s": 45.0, "river_discharge_3d_sum": 125.0, "river_discharge_7d_sum": 280.0, "river_discharge_15d_sum": 540.0
            },
            "Kasaragod": {
                "rainfall_mm": 20.0, "rainfall_mm_3d_sum": 55.0, "rainfall_mm_7d_sum": 115.0, "rainfall_mm_15d_sum": 180.0,
                "river_discharge": 40.0, "river_discharge_m3s": 40.0, "river_discharge_3d_sum": 110.0, "river_discharge_7d_sum": 250.0, "river_discharge_15d_sum": 480.0
            },
            "Palakkad": {
                "rainfall_mm": 18.0, "rainfall_mm_3d_sum": 48.0, "rainfall_mm_7d_sum": 98.0, "rainfall_mm_15d_sum": 160.0,
                "river_discharge": 45.0, "river_discharge_m3s": 45.0, "river_discharge_3d_sum": 120.0, "river_discharge_7d_sum": 270.0, "river_discharge_15d_sum": 510.0
            },
            "Kollam": {
                "rainfall_mm": 15.0, "rainfall_mm_3d_sum": 40.0, "rainfall_mm_7d_sum": 85.0, "rainfall_mm_15d_sum": 140.0,
                "river_discharge": 35.0, "river_discharge_m3s": 35.0, "river_discharge_3d_sum": 95.0, "river_discharge_7d_sum": 210.0, "river_discharge_15d_sum": 410.0
            },
            "Thiruvananthapuram": {
                "rainfall_mm": 12.0, "rainfall_mm_3d_sum": 32.0, "rainfall_mm_7d_sum": 70.0, "rainfall_mm_15d_sum": 120.0,
                "river_discharge": 30.0, "river_discharge_m3s": 30.0, "river_discharge_3d_sum": 80.0, "river_discharge_7d_sum": 180.0, "river_discharge_15d_sum": 350.0
            }
        }

    weather_url = "https://api.open-meteo.com/v1/forecast"
    flood_url = "https://flood-api.open-meteo.com/v1/flood"
    results = {}
    
    async with httpx.AsyncClient() as client:
        for district, coords in KERALA_DISTRICTS.items():
            try:
                weather_res = await client.get(
                    weather_url,
                    params={
                        "latitude": coords["lat"], 
                        "longitude": coords["lon"], 
                        "daily": "precipitation_sum", 
                        "past_days": 15,
                        "forecast_days": 1,
                        "timezone": "auto"
                    }
                )
                flood_res = await client.get(
                    flood_url,
                    params={
                        "latitude": coords["lat"], 
                        "longitude": coords["lon"], 
                        "daily": "river_discharge",
                        "past_days": 15,
                        "forecast_days": 1
                    }
                )
                
                precip_history = weather_res.json().get("daily", {}).get("precipitation_sum", [0.0] * 16)
                discharge_history = flood_res.json().get("daily", {}).get("river_discharge", [0.0] * 16)
                
                precip_history = [float(x) if x is not None else 0.0 for x in precip_history]
                discharge_history = [float(x) if x is not None else 0.0 for x in discharge_history]
                
                results[district] = {
                    "rainfall_mm": precip_history[-1],
                    "rainfall_mm_3d_sum": sum(precip_history[-3:]),
                    "rainfall_mm_7d_sum": sum(precip_history[-7:]),
                    "rainfall_mm_15d_sum": sum(precip_history[-15:]),
                    "river_discharge": discharge_history[-1],
                    "river_discharge_m3s": discharge_history[-1],
                    "river_discharge_3d_sum": sum(discharge_history[-3:]),
                    "river_discharge_7d_sum": sum(discharge_history[-7:]),
                    "river_discharge_15d_sum": sum(discharge_history[-15:])
                }
            except Exception as e:
                print(f"Failed to fetch Meteo data for {district}: {e}")
                results[district] = {
                    "rainfall_mm": 0.0, "rainfall_mm_3d_sum": 0.0, "rainfall_mm_7d_sum": 0.0, "rainfall_mm_15d_sum": 0.0,
                    "river_discharge": 0.0, "river_discharge_m3s": 0.0, "river_discharge_3d_sum": 0.0, "river_discharge_7d_sum": 0.0, "river_discharge_15d_sum": 0.0
                }
                
    return results

async def scrape_kseb_dam_levels():
    scraped_dams = [
        {"dam_name": "Idukki", "current_level_m": 239.5, "capacity_pct": 78.2, "status": "NORMAL", "outflow_m3s": 0},
        {"dam_name": "Mullaperiyar", "current_level_m": 136.2, "capacity_pct": 85.0, "status": "WARNING", "outflow_m3s": 150}
    ]
    
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        
        async with httpx.AsyncClient(verify=False, follow_redirects=True) as client:
            res = await client.get("https://sldckerala.com/index.php?id=7", headers=headers, timeout=10.0)
            
            if res.status_code == 200:
                soup = BeautifulSoup(res.text, 'html.parser')
                table = soup.find('table')
                if table:
                    live_data = []
                    rows = table.find_all('tr')
                    target_dams = ["IDUKKI", "PAMBA", "SHOLAYAR", "IDAMALAYAR", "KUTTIADI"]
                    
                    for row in rows:
                        cols = row.find_all(['td', 'th'])
                        row_text = " ".join([c.text.strip().upper() for c in cols])
                        
                        for dam in target_dams:
                            if dam in row_text and len(cols) >= 4:
                                try:
                                    texts = [c.text.strip() for c in cols if c.text.strip()]
                                    level_val = 0.0
                                    pct_val = 0.0
                                    
                                    for t in texts:
                                        cleaned = t.replace('%', '').strip()
                                        try:
                                            val = float(cleaned)
                                            if 10 < val < 3000 and level_val == 0.0:
                                                level_val = val
                                            elif 0 <= val <= 100 and pct_val == 0.0 and val != level_val:
                                                pct_val = val
                                        except ValueError:
                                            continue
                                            
                                    if level_val > 0:
                                        live_data.append({
                                            "dam_name": dam.capitalize(),
                                            "current_level_m": level_val,
                                            "capacity_pct": pct_val if pct_val > 0 else 50.0,
                                            "status": "CRITICAL" if pct_val > 90 else "WARNING" if pct_val > 75 else "NORMAL",
                                            "outflow_m3s": 0.0
                                        })
                                except Exception:
                                    continue
                                    
                    if len(live_data) > 0:
                        unique_dams = {d["dam_name"]: d for d in live_data}.values()
                        scraped_dams = list(unique_dams)
                        print("✅ Successfully scraped live dam data from SLDC!")
    except Exception as e:
        print(f"⚠️ Live Scraper warning: {e}. Falling back to default data.")
        
    return scraped_dams