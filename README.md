
# namesilo_ddns
* This is a Bash script to update Namesilo's DNS record when the IP changes

## Prerequisites:
* Generate API key in the [api manager](https://www.namesilo.com/account_api.php) at Namesilo 
* Make sure your system have command `dig` and `xmllint`. If not, install them:
    * on CentOS: ```sudo yum install bind-utils libxml2```
    * on Ubuntu/Debian: ```sudo apt-get install dnsutils libxml2-utils```
    * on Arch Linux ```pacman -Sy libxml2 dnsutils```

# Usage
* Download and save the Bash script
* Set file permission to make it executable ```chmod +x namesilo_ddns.sh```
* Write your namesilo API Key into a file named ```namesilo_api.key``` in the same directory as the script
* Start Script with ```./namesilo_ddns example.com``` or ```./namesilo_ddns example.com subdomain```
* Create cronjob (optional)
