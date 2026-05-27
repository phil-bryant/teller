import Foundation

extension ClassificationViewModel {
    // #R001: Match-review extension participates in shared load behavior after selection changes.
    // #R005: Match-review interactions preserve selected-row classification mutation semantics.
    // #R010: Match-review flows preserve optimistic-save rollback semantics in shared state.
    // #R015: Match-review composition preserves keyboard-triage and undo behaviors.
    // #R020: Match-review composition preserves paged transaction merge behavior.
    // #R025: Match-review composition preserves default unclassified-filter startup behavior.
    // #R030: Match-review composition preserves category-editor delete behavior contracts.
    // #R035: Match-review extension owns clear-selected-match behavior and unmatched transitions.
    // #R040: Match-review extension owns debounced Mailcart search + error/result surface behavior.
    // #R075: Match-review composition preserves background accurate-total refresh behavior.
    // #R080: Match-review composition preserves optional transaction-list profiling behavior.
    // #R085: Match-review logic is split into this focused extension without behavior changes.
    // #R090: Match-review composition preserves advanced transaction filter forwarding behavior.
    // #R095: Match-review extension owns structured debounced Mailcart search criteria behavior.
    /// Triggered whenever the primary selected transaction changes. Loads the candidate set + email
    /// for the primary transaction so the right pane stays in sync with the left pane.
    func selectedTransactionDidChange() async {
        guard let row = primaryTransaction else {
            candidatesLoadToken = nil
            emailLoadToken = nil
            candidates = []
            selectedCandidateId = nil
            selectedEmail = nil
            lastLoadedCandidatesTransactionId = nil
            return
        }
        if lastLoadedCandidatesTransactionId == row.transaction_id, !candidates.isEmpty { return }
        // Clear pane state eagerly to prevent stale candidate/email content while loading.
        candidates = []
        mailcartSearchResults = []
        selectedCandidateId = nil
        selectedEmail = nil
        candidatesErrorText = ""
        emailErrorText = ""
        await loadCandidatesForPrimaryTransaction()
    }

    // #R040 #R095: Debounce structured Mailcart search input and populate results or surface API errors.
    func searchMailcartIfNeeded() async {
        let criteria = mailcartSearchCriteria.normalized()
        guard criteria.hasActiveFilter else {
            mailcartSearchResults = []
            mailcartSearchErrorText = ""
            mailcartSearchBusy = false
            return
        }
        let token = UUID()
        mailcartSearchTaskToken = token
        mailcartSearchBusy = true
        try? await Task.sleep(nanoseconds: Self.mailcartSearchDebounceNanoseconds)
        guard mailcartSearchTaskToken == token else { return }
        do {
            let response = try await api.searchMessages(criteria: criteria, limit: 25)
            guard mailcartSearchTaskToken == token else { return }
            mailcartSearchResults = response.items
            mailcartSearchErrorText = ""
        } catch {
            guard mailcartSearchTaskToken == token else { return }
            mailcartSearchResults = []
            mailcartSearchErrorText = error.localizedDescription
        }
        if mailcartSearchTaskToken == token { mailcartSearchBusy = false }
    }

    func confirmSelectedMatch() async {
        let trimmedNote = matchOverrideNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = trimmedNote.isEmpty ? nil : trimmedNote
        do {
            if let matchId = selectedMatchId {
                _ = try await api.confirmMatch(matchId: matchId)
                matchReviewStatusText = "Confirmed match \(matchId)"
            } else if let transactionId = primaryTransaction?.transaction_id,
                      let emailId = overrideTargetEmailMessageId {
                let response = try await api.confirmTransactionCandidate(
                    transactionId: transactionId,
                    emailMessageId: emailId,
                    note: note
                )
                matchReviewStatusText = "Confirmed candidate for \(response.transaction_id)"
            } else {
                matchReviewErrorText = "Select a candidate before confirming."
                matchReviewStatusText = "Match confirm failed"
                return
            }
            matchReviewErrorText = ""
            matchOverrideEmailMessageId = ""
            matchOverrideNote = ""
            lastLoadedCandidatesTransactionId = nil
            await loadAll()
        } catch {
            matchReviewErrorText = error.localizedDescription
            matchReviewStatusText = "Match confirm failed"
        }
    }

    func overrideSelectedMatch() async {
        guard let emailId = overrideTargetEmailMessageId, !emailId.isEmpty else {
            matchReviewErrorText = "Select a candidate (or paste a message id) before overriding."
            return
        }
        let trimmedNote = matchOverrideNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = trimmedNote.isEmpty ? "Overridden in Teller UI" : trimmedNote
        do {
            if let matchId = selectedMatchId {
                _ = try await api.overrideMatch(matchId: matchId, emailMessageId: emailId, note: note)
                matchReviewStatusText = "Overrode match \(matchId)"
            } else if let transactionId = primaryTransaction?.transaction_id {
                let response = try await api.overrideTransactionCandidate(
                    transactionId: transactionId,
                    emailMessageId: emailId,
                    note: note
                )
                matchReviewStatusText = "Assigned email to \(response.transaction_id)"
            } else {
                matchReviewErrorText = "Select a transaction before overriding."
                matchReviewStatusText = "Match override failed"
                return
            }
            matchReviewErrorText = ""
            matchOverrideEmailMessageId = ""
            matchOverrideNote = ""
            lastLoadedCandidatesTransactionId = nil
            await loadAll()
        } catch {
            matchReviewErrorText = error.localizedDescription
            matchReviewStatusText = "Match override failed"
        }
    }

    func markSelectedMatchNoEmail() async {
        do {
            if let matchId = selectedMatchId {
                _ = try await api.markMatchNoEmail(matchId: matchId)
                matchReviewStatusText = "Marked match \(matchId) as no-email"
            } else if let transactionId = primaryTransaction?.transaction_id {
                let response = try await api.markTransactionNoEmail(transactionId: transactionId)
                matchReviewStatusText = "Marked \(response.transaction_id) as no-email"
            } else {
                matchReviewErrorText = "Select a transaction before marking no-email."
                matchReviewStatusText = "No-email action failed"
                return
            }
            matchReviewErrorText = ""
            lastLoadedCandidatesTransactionId = nil
            await loadAll()
        } catch {
            matchReviewErrorText = error.localizedDescription
            matchReviewStatusText = "No-email action failed"
        }
    }

    // #R035: Deactivate the active match so the transaction returns to unmatched.
    func clearSelectedMatch() async {
        do {
            if let matchId = selectedMatchId {
                let response = try await api.clearMatch(matchId: matchId)
                matchReviewStatusText = "Cleared match \(matchId) for \(response.transaction_id)"
            } else if let transactionId = primaryTransaction?.transaction_id {
                let response = try await api.clearTransactionMatch(transactionId: transactionId)
                matchReviewStatusText = "Cleared match for \(response.transaction_id)"
            } else {
                matchReviewErrorText = "Select a transaction with an active match before clearing."
                matchReviewStatusText = "Match clear failed"
                return
            }
            matchReviewErrorText = ""
            matchOverrideEmailMessageId = ""
            matchOverrideNote = ""
            lastLoadedCandidatesTransactionId = nil
            await loadAll()
        } catch {
            matchReviewErrorText = error.localizedDescription
            matchReviewStatusText = "Match clear failed"
        }
    }

    private func loadCandidatesForPrimaryTransaction() async {
        guard let row = primaryTransaction else { return }
        candidatesBusy = true
        candidatesErrorText = ""
        let token = UUID()
        candidatesLoadToken = token
        defer {
            if candidatesLoadToken == token { candidatesBusy = false }
        }
        do {
            let rows = try await api.fetchCandidates(transactionId: row.transaction_id)
            guard candidatesLoadToken == token,
                  let current = primaryTransaction,
                  current.transaction_id == row.transaction_id else { return }
            candidates = rows
            lastLoadedCandidatesTransactionId = row.transaction_id
            let activeEmailId = row.match?.email_message_id
            let preferred = rows.first(where: { $0.email_message_id == activeEmailId })?.email_message_id
                ?? rows.first(where: { $0.is_selected_by_ai })?.email_message_id
                ?? rows.first?.email_message_id
            selectedCandidateId = preferred
            await selectedCandidateDidChange()
        } catch {
            guard candidatesLoadToken == token,
                  let current = primaryTransaction,
                  current.transaction_id == row.transaction_id else { return }
            candidates = []
            selectedCandidateId = nil
            selectedEmail = nil
            candidatesErrorText = error.localizedDescription
        }
    }

    func selectedCandidateDidChange() async {
        guard let candidateId = selectedCandidateId else {
            emailLoadToken = nil
            selectedEmail = nil
            return
        }
        emailBusy = true
        emailErrorText = ""
        let token = UUID()
        emailLoadToken = token
        defer {
            if emailLoadToken == token { emailBusy = false }
        }
        do {
            let message = try await api.fetchMessage(emailMessageId: candidateId)
            guard emailLoadToken == token, selectedCandidateId == candidateId else { return }
            selectedEmail = message
        } catch {
            guard emailLoadToken == token, selectedCandidateId == candidateId else { return }
            selectedEmail = nil
            emailErrorText = error.localizedDescription
        }
    }
}
