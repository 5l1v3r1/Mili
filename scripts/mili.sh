#!/bin/bash

PATH="$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:"
case $OSTYPE in
  darwin*)
    CONFIG=$(cat "/Users/<-USER->/.mili/config.json");;
  linux*)
    CONFIG=$(cat "/home/<-USER->/.mili/config.json");;
  *)
    echo "Mili not support your OS: $OSTYPE";;
esac
base_url=$(echo $CONFIG | jq -r '.base_url')

function get_status() {
  curl -s "$base_url/login" | grep "logged" > /dev/null
  return $?
}

function check_mikrotik() {
  curl -s "captive.apple.com" --connect-timeout 3 | grep "login required" > /dev/null
  return $?
}

function check_network_connection() {
  local default_interface=$(echo $CONFIG | jq -r '.default_interface')

  if [ $OSTYPE == 'darwin' ]; then
    ifconfig $default_interface | grep "inet" > /dev/null
    return $?
  else
    ip address | grep enp0s5 | grep inet > /dev/null
    return $?
  fi
}

function logout() {
  curl -s "$base_url/logout" > /dev/null
  return 0
}

function select_random_user() {
  local login_information=$1
  local length=$(echo $login_information | jq -r 'length')
  local sum_of_shares=$(echo $login_information | jq 'map(.share) | add')
  local random_number=$((RANDOM % ($sum_of_shares+1)))

  for i in $(seq 0 $(($length-1))); do
    local info=$(echo $login_information | jq ".[$i]")
    local share=$(echo $info | jq ".share")

    random_number=$(($random_number - $share))
    if [ $random_number -le 0 ]; then
      return $i
    fi
  done

  return 0
}

function login() {
  local username=$1
  local password=$2

  get_status
  if [ $? -eq 0 ]; then logout; fi;

  curl -s "$base_url/login?username=$username&password=$password" | grep "logged" >> /dev/null
  local successful=$?

  if [ $successful -eq 0 ]; then
    notify_user "Successfuly Login whit $username"
  fi
  return $successful
}

function login_using_login_info() {
  local login_information=$1
  local user_index=$2

  local user_info=$(echo $login_information | jq -r ".[$user_index]")
  local username=$(echo $user_info | jq -r '.username')
  local password=$(echo $user_info | jq -r '.password')

  login $username $password
  return $?
}

function random_login() {
  local login_information=$(echo $CONFIG | jq '.login_information')
  select_random_user "$login_information"
  login_using_login_info "$login_information" $?
  return $?
}

function try_all() {
  local login_information=$(echo $CONFIG | jq '.login_information')
  local length=$(echo $login_information | jq -r 'length')

  for i in $(seq 0 $(($length-1))); do
    login_using_login_info "$login_information" $i
    if [ $? -eq 0 ]; then
      return 0
    fi
  done

  return 1
}

function notify_user() {
  local message=$1

  if [ $OSTYPE == 'darwin' ]; then
    terminal-notifier -title Mili -message "$message" -open "$base_url/login" -sender com.apple.automator.Mili -group mili > /dev/null
  else
    local user="<-USER->"
    sudo -u $user DISPLAY=:0 "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $user)/bus" notify-send "Mili" "$message" -i "/home/sadegh/.mili/logo.png"
  fi

}

function auto_login() {
  check_network_connection
  if [ $? -eq 0 ]; then
    echo "Network [YES]"
  else
    echo "Network [NO]"
    return 0
  fi

  check_mikrotik
  if [ $? -eq 0 ]; then
    echo "Mikrotik [YES]"
  else
    echo "Mikrotik [NO]"
    return 0
  fi

  random_login
  if [ $? -eq 1 ]; then
    echo "RandomLogin [FAILED]"
  else
    echo "RandomLogin [SUCCESS]"
    return 0
  fi

  try_all
  if [ $? -eq 1 ]; then
    echo "TryAll [FAILED]"
  else
    echo "TryAll [SUCCESS]"
    return 0
  fi

  echo "Login [FAILED]"
  notify_user "There was a problem with your login request"
  return 1
}

auto_login
