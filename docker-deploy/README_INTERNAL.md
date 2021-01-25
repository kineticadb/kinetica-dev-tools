# Issues Encountered

## Problem 1

When trying to use `docker-deploy` on a newly installed computer (Pop!_OS),
encountered the following issues:

* docker was not installed
* docker-compose was not installed
* The docker daemon had not been started
  Solution:

   ``` > sudo service docker start   # for work with SysVinit
       > sudo systemctl start docker # for work with Systemd
   ```

* Could not use docker commands without sudo.  The solution was to add the user
  to the `docker` group.  The error was:

  ```Got permission denied while trying to connect to the Docker daemon socket at
     unix:///var/run/docker.sock: Get http://%2Fvar%2Frun%2Fdocker.sock/v1.40/containers/json:
     dial unix /var/run/docker.sock: connect: permission denied.
  ```

  First check if the docker group already exists on your Ubuntu system:

  ```> grep docker /etc/group
  ```

   If the group already in there, add the user to the docker group using the
   usermod command:

   ```> usermod -aG docker user_name```

   Make sure you replace the user_name with your own. To add yourself (the
   current logged in user), run:

   ```> usermod -aG docker $USER```

   The user needs to Log out and log back into the Ubuntu server so that group
   membership is re-evaluated. After that the user will be able to run Docker
   commands without using root or sudo.

   If the group does not exist, Create the docker group:

   ```> sudo groupadd docker```

   And restart the docker service:

   ```> sudo systemctl restart docker```

* yq was not installed.  Can't remember how I installed it now!
  To check whether it is available:

  ```> which yq```

* yq needed python 2 for it to work.  Solution was to install python2:

  ```> sudo apt install python2```

  Then create a soft symlink to it:

  ```> sudo /usr/bin
     > sudo ln -s python2 python
  ```

* If yq is not installed, then the script deletes everything in the
  `docker-deploy` directory.  (It prompts the user to delete it.)
