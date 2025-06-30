#!/bin/bash

set -e

echo "[1/5] Установка Python и pip..."
sudo apt update
sudo apt install -y python3 python3-pip git

echo "[2/5] Клонирование репозитория ArbiScanX..."
PROJECT_DIR="$HOME/arbiscanx"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

echo "[3/5] Инициализация файлов проекта..."
cat <<'EOF' > exchanges.py
import ccxt

exchange_ids = ['mexc', 'bybit', 'bingx', 'gate', 'binance', 'upbit']
exchanges = {}
for id in exchange_ids:
    cls = getattr(ccxt, id)
    exchanges[id] = cls({ 'enableRateLimit': True })
for ex in exchanges.values():
    ex.load_markets()
EOF

cat <<'EOF' > arbitrage.py
from exchanges import exchanges
import pandas as pd

def find_spot_arbitrage(threshold=0.5):
    common = set.intersection(*(set(ex.symbols) for ex in exchanges.values()))
    rows = []
    for symbol in common:
        try:
            prices = {eid: exchanges[eid].fetch_ticker(symbol)['last'] for eid in exchanges}
            min_e = min(prices, key=prices.get)
            max_e = max(prices, key=prices.get)
            spread = (prices[max_e] / prices[min_e] - 1) * 100
            if spread >= threshold:
                rows.append({
                    'symbol': symbol,
                    'buy_at':   f"{min_e}: {prices[min_e]:.8f}",
                    'sell_at':  f"{max_e}: {prices[max_e]:.8f}",
                    'spread%':  f"{spread:.4f}"
                })
        except Exception:
            pass
    return pd.DataFrame(rows)

if __name__ == "__main__":
    df = find_spot_arbitrage()
    print("✅ Spot Arbitrage Opportunities:")
    print(df.to_string(index=False) if not df.empty else "— none —")
EOF

cat <<'EOF' > funding.py
from exchanges import exchanges
import pandas as pd

def find_funding_spread(threshold=0.01):
    rows = []
    for eid, ex in exchanges.items():
        if hasattr(ex, 'fetch_funding_rate') or hasattr(ex, 'fetch_funding_rates'):
            try:
                # индивидуальные и многоразовые вызовы:
                frs = {}
                if hasattr(ex, 'fetch_funding_rates'):
                    frs = ex.fetch_funding_rates()
                else:
                    for sym in ex.symbols:
                        if sym.endswith('PERP') or 'USDT' in sym:
                            r = ex.fetch_funding_rate(sym)
                            if r: frs[sym] = r
                for sym, info in frs.items():
                    rate = info.get('fundingRate') or info.get('rate')
                    if rate and abs(rate) >= threshold:
                        rows.append({
                            'exchange': eid,
                            'symbol': sym,
                            'fundingRate': rate
                        })
            except Exception:
                pass
    return pd.DataFrame(rows)

if __name__ == "__main__":
    df = find_funding_spread()
    print("✅ Funding Rates (abs >= threshold):")
    print(df.to_string(index=False) if not df.empty else "— none —")
EOF

cat <<'EOF' > run.py
#!/usr/bin/env python3
from arbitrage import find_spot_arbitrage
from funding import find_funding_spread

def main():
    print("\n=== ArbiScanX ===\n")
    df_spot = find_spot_arbitrage()
    print("➤ Spot-Arbitrage:")
    print(df_spot.to_string(index=False) if not df_spot.empty else "No opportunities found.")
    print("\n➤ Funding-Rate Scan:")
    df_f = find_funding_spread()
    print(df_f.to_string(index=False) if not df_f.empty else "No notable funding rates.")

if __name__ == "__main__":
    main()
EOF

chmod +x run.py

echo "[4/5] Установка зависимостей Python..."
pip3 install --upgrade pip
pip3 install ccxt pandas

echo "[5/5] Установка завершена!"
echo "Запуск: cd \"$PROJECT_DIR\" && ./run.py"
