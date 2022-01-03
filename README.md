# Basic Nomad/Consul Setup
Here is a simple-ish script which stands up a server/client pair on Digital
Ocean Droplets. For configuring those droplets you can review the section below,
`Using Digital Ocean`.

You'll need to first spin up those two servers before the included script can be
successfully run. Of course, this will necessitate installing the Docker CLI
`doctl` and generating a token with your Docker account.

Once all of the above has been taken care of, all you need is the IP addresses
for the Droplets - one for the server and one for the client. When first pulling
this down you'll need to change permissions on the script so run `chmod u+x
bootstrap_nomad_droplets.sh`.

After all of that is complete run this command to start the bootstrapping
process:
`./bootstrap_nomad_droplets.sh SERVER_IP CLIENT_IP`
* Note that you'll want the server IP _first_ or you're going to have a bad
  time.

# Using Digital Ocean
Digital Ocean has a CLI which can allow for quicker operations when creating
and destroying Droplets.

https://www.digitalocean.com/community/tutorials/how-to-use-doctl-the-official-digitalocean-command-line-client

First, get the proper ssh-key fingerprint from your DO account:
`doctl compute ssh-key list`

Once you have the ssh-key fingerprint you can enter it into the commands below:
To create the server:
`doctl compute droplet create ubuntu-server-test --size s-1vcpu-1gb --image ubuntu-20-04-x64 --region sfo3 --ssh-keys [FINGERPRINT] --tag-name server`

To create the client:
`doctl compute droplet create ubuntu-client-test --size s-1vcpu-1gb --image ubuntu-20-04-x64 --region sfo3 --ssh-keys [FINGERPRINT] --tag-name client`

To view the currently active Droplets:
`doctl compute droplet list --format "ID,Name,PublicIPv4"`

To delete a Droplet:
`doctl compute droplet delete [ID]`
