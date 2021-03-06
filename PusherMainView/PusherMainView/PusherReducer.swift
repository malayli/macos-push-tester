import Foundation

struct PusherReducer {
    func reduce(actionType: ActionType, state: PusherState) -> PusherState {
        var newState = state
        
        switch actionType {
        case .selectDevice(let device):
            newState.deviceTokenString = device.token
            newState.appID = device.appID
            
        case .chooseAuthToken:
            newState.certificateRadioState = .off
            newState.authTokenRadioState = .on
            
        case .cancelAuthToken:
            newState.authTokenRadioState = .off
            
        case .saveAuthToken:
            newState.authTokenRadioState = .on
            
        case .chooseIdentity:
            newState.certificateRadioState = .on
            newState.authTokenRadioState = .off
            
        case .cancelIdentity:
            newState.certificateRadioState = .off
            
        case .updateIdentity:
            newState.certificateRadioState = .on
            
        default: ()
        }
        
        return newState
    }
}
