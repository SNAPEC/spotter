# At debug level Action Mailer logs every mail in full, recipient included: a declarant's address would
# sit in the log next to the job that names their report. Mail deliveries are not logged at all.
ActiveSupport.on_load(:action_mailer) { self.logger = nil }
