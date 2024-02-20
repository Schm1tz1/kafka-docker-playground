# GCP Firebase Source connector



## Objective

Quickly test [GCP Firebase Source](https://docs.confluent.io/current/connect/kafka-connect-firebase/source/index.html#quick-start) connector.


* Active Google Cloud Platform (GCP) account with authorization to create resources

## GCP Firebase Setup

### Service Account setup

Create `Service Account` from IAM & Admin console:

Set `Service account name`:

![Service Account setup](Screenshot1.png)

Choose permission `Firebase`->`Firebase Realtime Database Viewer`

![Service Account setup](Screenshot2.png)

Create Key:

![Service Account setup](Screenshot3.png)

Download it as JSON:

![Service Account setup](Screenshot4.png)

Rename it to `keyfile.json` and place it in `./keyfile.json`


### Realtime Database setup

Go to [Firebase console](https://console.firebase.google.com), click `Add Project` and choose your GCP project.

In your console, click `Database`on the left sidebar:

![Realtime Database setup](Screenshot5.png)

Click on `Realtime Database`:

![Realtime Database setup](Screenshot6.png)

Click on `Enable`:

![Realtime Database setup](Screenshot7.png)

Click on vertical dots on the right hand side and choose `Import JSON`:

![Realtime Database setup](Screenshot8.png)

Browse to file `./musicBlog.json` and import it

![Realtime Database setup](Screenshot9.png)

You should see:

![Realtime Database setup](Screenshot10.png)

## How to run

Simply run:

```bash
$ playground run -f gcp-firebase-source<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> <GCP_PROJECT>
```