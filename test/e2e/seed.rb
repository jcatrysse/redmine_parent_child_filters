# frozen_string_literal: true

# Data for this plugin's end-to-end scenarios, run by .codex/start_server.sh
# after the generic seed (.codex/e2e/seed.rb), whose users and projects it uses.
# Idempotent: running it again changes nothing.
#
# Every issue here is named "PCF ..." so the scenarios can find them by subject.
#
#   e2e-project
#     PCF Epic (Feature, New)
#       PCF Story (Support, In Progress)
#         PCF Task open (Bug, New)
#         PCF Task closed (Bug, Closed)
#     PCF Standalone (Support, New)                     no relatives
#     PCF Parent of hidden (Feature, New)
#       PCF Hidden child (Bug, New), in e2e-private      invisible to reporter
#     PCF Mention (Support)                             "@reporter" in the description,
#                                                       "user#<manager>" in a note,
#                                                       "@admin" in a private note only
#     PCF Watched (Support)                             watched by reporter and by manager
#     PCF Dated (Support)                               start date 2026-01-15
#     PCF Browser parent > PCF Browser child           moved by the scenario
#     PCF Silent parent > PCF Silent child             moved with the journaling off
#   e2e-history (public)
#     PCF Moved parent > PCF Moved child               created in e2e-project, moved here

admin = User.find_by!(login: 'admin')
manager = User.find_by!(login: 'manager')
reporter = User.find_by!(login: 'reporter')
User.current = admin

project = Project.find_by!(identifier: 'e2e-project')
private_project = Project.find_by!(identifier: 'e2e-private')

# A subtask in another project tree is what makes "a relative you cannot see" testable.
Setting.cross_project_subtasks = 'system'
Setting.webhooks_enabled = '1' if Setting.respond_to?(:webhooks_enabled=)

history = Project.find_by(identifier: 'e2e-history') ||
          Project.new(identifier: 'e2e-history', name: 'E2E history', description: 'Target of the moves.')
history.is_public = true
history.enabled_module_names = %w[issue_tracking]
history.trackers = Tracker.all
history.save!
full = Role.find_by!(name: 'E2E full')
reporter_role = Role.find_by(name: 'Reporter')
Member.create!(principal: manager, project: history, roles: [full]) unless Member.where(user_id: manager.id, project_id: history.id).exists?
Member.create!(principal: reporter, project: history, roles: [reporter_role]) if reporter_role && !Member.where(user_id: reporter.id, project_id: history.id).exists?

def pcf_tracker(name)
  Tracker.find_by!(name: name)
end

def pcf_status(name)
  IssueStatus.find_by!(name: name)
end

def pcf_issue(subject, project:, tracker:, status: 'New', parent: nil, author: User.current, attrs: {})
  issue = Issue.find_by(subject: subject)
  return issue if issue

  issue = Issue.new(project: project, tracker: pcf_tracker(tracker), subject: subject, author: author,
                    priority: IssuePriority.default || IssuePriority.first)
  issue.status = pcf_status(status)
  issue.parent_issue_id = parent.id if parent
  attrs.each { |k, v| issue.send("#{k}=", v) }
  issue.save!
  issue.reload
end

epic = pcf_issue('PCF Epic', project: project, tracker: 'Feature')
story = pcf_issue('PCF Story', project: project, tracker: 'Support', status: 'In Progress', parent: epic)
pcf_issue('PCF Task open', project: project, tracker: 'Bug', parent: story)
pcf_issue('PCF Task closed', project: project, tracker: 'Bug', status: 'Closed', parent: story)
pcf_issue('PCF Standalone', project: project, tracker: 'Support')

hidden_parent = pcf_issue('PCF Parent of hidden', project: project, tracker: 'Feature')
pcf_issue('PCF Hidden child', project: private_project, tracker: 'Bug', parent: hidden_parent)

mention = pcf_issue('PCF Mention', project: project, tracker: 'Support',
                                   attrs: { description: 'Ask @reporter about this.' })
if mention.journals.none?
  mention.init_journal(admin, "Linked to user##{manager.id} for the follow-up.")
  mention.save!
  # init_journal keeps returning the journal of the same object, so a fresh one.
  mention = Issue.find(mention.id)
  journal = mention.init_journal(admin, 'Private: only @admin should know.')
  journal.private_notes = true
  mention.save!
end

watched = pcf_issue('PCF Watched', project: project, tracker: 'Support')
[reporter, manager].each { |u| watched.add_watcher(u) unless watched.watched_by?(u) }

pcf_issue('PCF Dated', project: project, tracker: 'Support', attrs: { start_date: Date.new(2026, 1, 15) })

browser_parent = pcf_issue('PCF Browser parent', project: project, tracker: 'Feature')
pcf_issue('PCF Browser child', project: project, tracker: 'Bug', parent: browser_parent)
silent_parent = pcf_issue('PCF Silent parent', project: project, tracker: 'Feature')
pcf_issue('PCF Silent child', project: project, tracker: 'Bug', parent: silent_parent)

moved_parent = pcf_issue('PCF Moved parent', project: project, tracker: 'Feature')
pcf_issue('PCF Moved child', project: project, tracker: 'Bug', parent: moved_parent)
if moved_parent.project_id == project.id
  moved_parent = Issue.find(moved_parent.id)
  moved_parent.init_journal(manager)
  moved_parent.project = history
  moved_parent.save!
end

# Redmine 7 webhooks: a hook owned by manager on both projects, posting to a
# listener the webhooks scenario starts on port 3999. Core refuses loopback
# targets, so it points at this machine's own non-loopback address.
if defined?(Webhook)
  ip = Socket.ip_address_list.find { |a| a.ipv4? && !a.ipv4_loopback? && !a.ipv4_multicast? }&.ip_address
  if ip
    hook = Webhook.find_or_initialize_by(user_id: manager.id, url: "http://#{ip}:3999/pcf")
    hook.events = %w[issue.created issue.updated]
    hook.active = true
    hook.projects = [project, history]
    hook.save!
  end
end

puts "PCF seed: #{Issue.where('subject LIKE ?', 'PCF %').count} issues, " \
     "ids #{Issue.where('subject LIKE ?', 'PCF %').order(:id).pluck(:subject, :id).map { |s, i| "#{s}=#{i}" }.join(', ')}"
