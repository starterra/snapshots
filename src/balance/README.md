## Script periodically collecting data from wallet containing STT to burn.

- Data is gathered by querying the current block, three times a day in an 8 hour interval.

- CSV file name consists of "STT_TOKEN_" prefix and year and month of data in it.

- Output contains the time of creation block that gets queried and the amount of STT on it.

- Crontab entry: 
```
# gather balance of STT Token every 8 hours
0 */8 * * * /home/terrad/scripts/balance/balance.sh >/dev/null 2>&1
```
