# Notification Setup Guide

## Discord Setup

1. In Discord:
- Create a channel for notifications
- Edit Channel > Integrations > Create Webhook
- Name it "[Service] Notifications"
- Copy the webhook URL

2. In each *arr service:
- Go to Settings > Connect
- Click "+"
- Select Discord
- Name: Discord Notifications
- Webhook URL: (paste from Discord)
- Enable notifications for:
  - On Grab
  - On Import
  - On Upgrade
  - On Health Issue
  - Include Health Warnings
- Tags: @here (optional)

3. Test the connection 

## Email Setup
1. In each *arr service:
- Go to Settings > Connect
- Click "+" > Select "Email"
- Configure:
  - Name: Email Notifications
  - Server: smtp.gmail.com (for Gmail)
  - Port: 587
  - Use SSL: Yes
  - Username: your.email@gmail.com
  - Password: (app-specific password)
  - From Address: your.email@gmail.com
  - Recipient Address: your.email@gmail.com
- Enable notifications for:
  - On Grab
  - On Import
  - On Upgrade
  - On Health Issue
- Test and Save

## Telegram Setup
1. In Telegram:
- Message @BotFather
- Use /newbot command
- Choose a name and username
- Copy the API Token

2. Get Chat ID:
- Message @userinfobot
- Copy your Chat ID

3. In each *arr service:
- Go to Settings > Connect
- Click "+" > Select "Telegram"
- Configure:
  - Name: Telegram Notifications
  - Bot Token: (paste API Token)
  - Chat ID: (paste Chat ID)
- Enable notifications for:
  - On Grab
  - On Import
  - On Upgrade
  - On Health Issue
- Test and Save 