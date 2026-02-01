# jira_api
Ruby script to search jira issues

Search by username
ruby jira_app.rb --assignee mihall3

Search by single label
ruby jira_app.rb --label security

Search by Multiple labels (match ANY / OR) (default)
ruby jira_app.rb --labels security,urgent --match-all

Search by Multiple labels (match ALL / AND)
ruby jira_app.rb --labels security,urgent
