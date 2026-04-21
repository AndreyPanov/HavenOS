/// Errors from facade operations.
public enum FacadeError: Error, Sendable {
    /// The requested action is not available in the current state.
    case actionNotAvailable(String)
    /// The backend adapter reported a failure.
    case adapterError(String)
}
