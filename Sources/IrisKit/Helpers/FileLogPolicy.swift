/// Persistent diagnostics describe behavior only. Never render an error or
/// inspect its associated values here: they can hold credentials or mail.
public enum FileLogPolicy {
    /// Arguments exclude the executable name.
    public static func writesFiles(arguments: [String]) -> Bool {
        arguments.drop(while: { $0 == "--" }).first != "ro"
    }

    /// Exhaustive on purpose: each new IrisError needs a fixed safe code.
    /// Unknown errors never contribute their description or type name.
    public static func failureCode(_ error: Error) -> String {
        guard let error = error as? IrisError else { return "command_failed" }
        switch error {
        case .noAccountsConfigured: return "no_accounts_configured"
        case .unknownAccount: return "unknown_account"
        case .accountNotChosen: return "account_not_chosen"
        case .missingSetting: return "missing_setting"
        case .invalidSetting: return "invalid_setting"
        case .messageNotParsed: return "message_not_parsed"
        case .htmlNotConverted: return "html_not_converted"
        case .draftRecipientsMissing: return "draft_recipients_missing"
        case .draftRecipientInvalid: return "draft_recipient_invalid"
        case .draftSubjectInvalid: return "draft_subject_invalid"
        case .notADraft: return "not_a_draft"
        case .draftUpdateNeedsUIDPlus: return "draft_update_needs_uidplus"
        case .draftNotPreserved: return "draft_not_preserved"
        case .draftUpdateMayBeSaved: return "draft_update_may_be_saved"
        case .draftUpdateIncomplete: return "draft_update_incomplete"
        case .draftBodyGivenTwice: return "draft_body_given_twice"
        case .draftBodyMissing: return "draft_body_missing"
        case .draftBodyEmpty: return "draft_body_empty"
        case .draftBodyNotRead: return "draft_body_not_read"
        case .draftBodyNotUTF8: return "draft_body_not_utf8"
        case .draftFromAddressMissing: return "draft_from_address_missing"
        case .draftsMailboxNotFound: return "drafts_mailbox_not_found"
        case .draftTooLarge: return "draft_too_large"
        case .draftMayBeSaved: return "draft_may_be_saved"
        case .draftAttachmentNotRead: return "draft_attachment_not_read"
        case .draftAttachmentIsAFolder: return "draft_attachment_is_a_folder"
        case .draftBodyNamesAFile: return "draft_body_names_a_file"
        case .draftRefused: return "draft_refused"
        case .loginFailed: return "login_failed"
        case .connectionFailed: return "connection_failed"
        case .connectionLost: return "connection_lost"
        case .unknownMailbox: return "unknown_mailbox"
        case .unknownMessage: return "unknown_message"
        case .invalidIrisID: return "invalid_iris_id"
        case .invalidPage: return "invalid_page"
        case .invalidLimit: return "invalid_limit"
        case .invalidDate: return "invalid_date"
        case .messageDownloadTimedOut: return "message_download_timed_out"
        case .bodyDownloadTimedOut: return "body_download_timed_out"
        case .bodyNotReceived: return "body_not_received"
        case .serverTimedOut: return "server_timed_out"
        case .searchFailed: return "search_failed"
        case .serverError: return "server_error"
        case .invalidAttachmentID: return "invalid_attachment_id"
        case .unknownAttachment: return "unknown_attachment"
        case .attachmentStructureMissing: return "attachment_structure_missing"
        case .attachmentDownloadTimedOut: return "attachment_download_timed_out"
        case .attachmentNotReceived: return "attachment_not_received"
        case .attachmentStdoutIsTerminal: return "attachment_stdout_is_terminal"
        case .attachmentOutputIsFolder: return "attachment_output_is_folder"
        case .attachmentFileExists: return "attachment_file_exists"
        case .attachmentNotSaved: return "attachment_not_saved"
        case .noGoogleAccounts: return "no_google_accounts"
        case .googleNotSignedIn: return "google_not_signed_in"
        case .googleSignInExpired: return "google_sign_in_expired"
        case .googleClientRejected: return "google_client_rejected"
        case .googleTokenFailed: return "google_token_failed"
        case .googleSignInFailed: return "google_sign_in_failed"
        case .googleNoRefreshToken: return "google_no_refresh_token"
        case .googleLoginRefused: return "google_login_refused"
        }
    }
}
