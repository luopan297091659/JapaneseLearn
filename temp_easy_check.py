#!/usr/bin/env python3
import json, sys

# Check NHK Easy News list
try:
    data = json.load(open('/tmp/easy_list.json'))
    # The response might be an array or dict keyed by date
    if isinstance(data, list) and len(data) > 0 and isinstance(data[0], dict):
        # It's a list of articles directly
        print(f'Articles in list: {len(data)}')
        a = data[0]
        print(f'Keys: {list(a.keys())}')
        print(f'ID: {a.get("news_id", "?")}')
        print(f'Title: {a.get("title", "?")[:100]}')
    elif isinstance(data, dict):
        keys = list(data.keys())
        print(f'Dates: {len(keys)}')
        if keys:
            date = keys[0]
            arts = data[date]
            if isinstance(arts, list) and len(arts) > 0:
                a = arts[0]
                print(f'Date: {date}, Articles: {len(arts)}')
                print(f'Keys: {list(a.keys())}')
                print(f'ID: {a.get("news_id", "?")}')
                print(f'Title: {a.get("title", "?")[:100]}')
                print(f'Has body: {"news_web_url" in a or "body" in a}')
                # Print all fields
                for k, v in a.items():
                    val = str(v)[:100] if v else ''
                    print(f'  {k}: {val}')
    else:
        print(f'Unknown format: type={type(data)}')
        print(str(data)[:500])
except Exception as e:
    print(f'Error: {e}')
    # Check raw file
    raw = open('/tmp/easy_list.json', 'r', encoding='utf-8').read()
    print(f'File length: {len(raw)}')
    print(f'First 500: {raw[:500]}')
