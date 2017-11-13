# te-agent-diag-and-restore

Helper script that collects and uploads ThousandEyes Enterprise Agent diagnostics data and fixes corrupted cache database.



## 1. Data collection

To collect and upload diagnostic data, copy and paste the following into the agent SSH console:

    curl   -o te-agent-diag-and-restore https://raw.githubusercontent.com/bostjan/te-agent-diag-and-restore/master/te-agent-diag-and-restore.sh &&
    chmod 755 te-agent-diag-and-restore &&
    ./te-agent-diag-and-restore

At the end of output there will be an URL that can be used to download the collected data.
Send that URL to support@thousandeyes.com.



## 2. "My agent is behind proxy"

No worries. Execute the following command before you run the data collection commands listed above.

For proxy without authentication (replace `PROXY` and `PORT` with appropriate values for your network):

    export https_proxy="http://PROXY:PORT/"


For proxy _with_ authentication (replace `USER` and `PASS` too, in addition to `PROXY` and `PORT`):

    export https_proxy="http://USER:PASS@PROXY:PORT/"


Now run the commands from section **1. Data collection** above.
