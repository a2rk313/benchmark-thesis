import json, glob, pandas as pd
files = glob.glob("results_*.json")
data = []

for f in files:
    name = f.replace("results_", "").replace(".json", "")
    with open(f) as jf:
        res = json.load(jf)
        for r in res['results']:
            data.append({
                "Benchmark": name,
                "Language": r['command'].split()[0],
                "Mean_Sec": round(r['mean'], 4),
                "Min_Sec": round(r['min'], 4),
                "Max_Sec": round(r['max'], 4)
            })

df = pd.DataFrame(data)
df.sort_values(by=["Benchmark", "Mean_Sec"], inplace=True)
df.to_csv("final_results.csv", index=False)
