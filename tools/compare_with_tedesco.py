#!/usr/bin/env python3
"""
Compare your matrix operation results with Tedesco et al. (2025)
"""

import json
import pandas as pd

TEDESCO_RESULTS = {
    'crossproduct': {'Python_NumPy': 0.033, 'Julia': 0.182, 'R_OpenBLAS': 0.034},
    'determinant':  {'Python_NumPy': 0.118, 'Julia': 0.152, 'R_OpenBLAS': 0.044},
    'sorting':      {'Python': 0.007,       'Julia': 0.031, 'R': 0.077}
}

def load_your_results():
    your = {}
    for lang in ['python', 'julia', 'r']:
        with open(f'results/matrix_ops_{lang}.json') as f:
            data = json.load(f)
            your[lang] = data['results']
    return your

def compare(your):
    comparison = []
    for task in ['crossproduct', 'determinant', 'sorting']:
        row = {'Task': task.capitalize()}
        row['Your_Python'] = your['python'][task]['min']
        row['Your_Julia'] = your['julia'][task]['min']
        row['Your_R'] = your['r'][task]['min']
        row['Tedesco_Python'] = TEDESCO_RESULTS[task].get('Python_NumPy', TEDESCO_RESULTS[task].get('Python'))
        row['Tedesco_Julia'] = TEDESCO_RESULTS[task]['Julia']
        row['Tedesco_R'] = TEDESCO_RESULTS[task].get('R_OpenBLAS', TEDESCO_RESULTS[task].get('R'))
        row['Ratio_Python'] = row['Your_Python'] / row['Tedesco_Python']
        row['Ratio_Julia'] = row['Your_Julia'] / row['Tedesco_Julia']
        row['Ratio_R'] = row['Your_R'] / row['Tedesco_R']
        comparison.append(row)
    df = pd.DataFrame(comparison)
    print("\n" + "="*100)
    print("COMPARISON WITH TEDESCO ET AL. (2025)")
    print("="*100)
    print(df.to_string(index=False))
    print("\nInterpretation: Ratio ≈ 1.0 validates findings.")
    with open('results/tedesco_comparison.txt', 'w') as f:
        f.write(df.to_string(index=False))

if __name__ == "__main__":
    your = load_your_results()
    compare(your)
