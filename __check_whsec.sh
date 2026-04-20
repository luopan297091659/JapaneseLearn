#!/bin/bash
python3 -c "
import json
d = json.load(open('/home/japanese-learn/backend/config/membership.json'))
s = d['payment'].get('stripe_webhook_secret') or ''
print('len=', len(s), 'prefix=', s[:10], 'is_whsec=', s.startswith('whsec_'))
"
