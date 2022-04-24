## Script periodically collecting data from Single Assets Staking blocks.

- Data is gathered by querying current block, at 3 AM CET.

- CSV file name consists of "STTSAA_" prefix and queried block number.

- Output contains Staker's wallet address and amount of STT bound on it.

- Crontab entry:
```
# gather Single Assets Staking data every 1AM UTC
0 1 * * * /home/terrad/scripts/sttsaa/sttsaa.sh >/dev/null 2>&1
```
