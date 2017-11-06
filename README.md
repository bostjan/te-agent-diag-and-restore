# te-agent-diag-and-restore

Helper script that collects and uploads ThousandEyes Enterprise Agent diagnostics data and fixes corrupted cache database.

To collect and upload diagnostic data, copy paste the following into the agent SSH console:

    rm -f     te-agent-diag-and-restore.sh &&
    curl -o   te-agent-diag-and-restore.sh https://github.com/bostjan/te-agent-diag-and-restore/raw/te-agent-diag-and-restore.sh  &&
    chmod 755 te-agent-diag-and-restore.sh  &&
    ./te-agent-diag-and-restore.sh

The last line of output will be an URL that can be used to download the data.
Copy the URL and send it to support@thousandeyes.com.
