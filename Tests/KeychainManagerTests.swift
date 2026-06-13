import XCTest
@testable import RioAgent

final class KeychainManagerTests: XCTestCase {
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        // Clean up any existing test keys
        try? KeychainManager.delete(forKey: "test_key")
        try? KeychainManager.delete(forKey: "test_key_2")
    }
    
    override func tearDown() {
        // Clean up test keys
        try? KeychainManager.delete(forKey: "test_key")
        try? KeychainManager.delete(forKey: "test_key_2")
        super.tearDown()
    }
    
    // MARK: - Save & Load Tests
    
    func testSaveAndLoad() throws {
        let testValue = "test_api_key_12345"
        let testKey = "test_key"
        
        // Save
        try KeychainManager.save(testValue, forKey: testKey)
        
        // Load
        let loadedValue = KeychainManager.load(forKey: testKey)
        
        XCTAssertEqual(loadedValue, testValue, "Loaded value should match saved value")
    }
    
    func testLoadNonExistentKey() {
        let loadedValue = KeychainManager.load(forKey: "non_existent_key_\(UUID().uuidString)")
        
        XCTAssertNil(loadedValue, "Loading non-existent key should return nil")
    }
    
    func testSaveOverwritesExisting() throws {
        let key = "test_key"
        let value1 = "first_value"
        let value2 = "second_value"
        
        // Save first value
        try KeychainManager.save(value1, forKey: key)
        
        // Save second value (should overwrite)
        try KeychainManager.save(value2, forKey: key)
        
        // Load should return second value
        let loadedValue = KeychainManager.load(forKey: key)
        XCTAssertEqual(loadedValue, value2, "Overwritten value should be returned")
    }
    
    // MARK: - Delete Tests
    
    func testDelete() throws {
        let key = "test_key"
        let value = "test_value"
        
        // Save then delete
        try KeychainManager.save(value, forKey: key)
        try KeychainManager.delete(forKey: key)
        
        // Should be nil after deletion
        let loadedValue = KeychainManager.load(forKey: key)
        XCTAssertNil(loadedValue, "Deleted key should return nil")
    }
    
    func testDeleteNonExistentKey() throws {
        // Deleting non-existent key should not throw
        try KeychainManager.delete(forKey: "non_existent_key_\(UUID().uuidString)")
    }
    
    // MARK: - Exists Tests
    
    func testExists() throws {
        let key = "test_key"
        let value = "test_value"
        
        // Before save
        XCTAssertFalse(KeychainManager.exists(forKey: key), "Key should not exist before save")
        
        // After save
        try KeychainManager.save(value, forKey: key)
        XCTAssertTrue(KeychainManager.exists(forKey: key), "Key should exist after save")
        
        // After delete
        try KeychainManager.delete(forKey: key)
        XCTAssertFalse(KeychainManager.exists(forKey: key), "Key should not exist after delete")
    }
    
    // MARK: - API Key Convenience Methods Tests
    
    func testSaveAndLoadAPIKey() throws {
        let apiKey = "sk-test-api-key-12345"
        
        try KeychainManager.saveAPIKey(apiKey, for: .claude)
        
        let loadedKey = KeychainManager.loadAPIKey(for: .claude)
        XCTAssertEqual(loadedKey, apiKey, "API key should match")
        
        // Cleanup
        try KeychainManager.deleteAPIKey(for: .claude)
    }
    
    func testDeleteAPIKey() throws {
        let apiKey = "sk-test-api-key-12345"
        
        try KeychainManager.saveAPIKey(apiKey, for: .openAI)
        try KeychainManager.deleteAPIKey(for: .openAI)
        
        let loadedKey = KeychainManager.loadAPIKey(for: .openAI)
        XCTAssertNil(loadedKey, "Deleted API key should return nil")
    }
    
    // MARK: - Multiple Keys Tests
    
    func testMultipleKeys() throws {
        let key1 = "test_key"
        let key2 = "test_key_2"
        let value1 = "value_1"
        let value2 = "value_2"
        
        try KeychainManager.save(value1, forKey: key1)
        try KeychainManager.save(value2, forKey: key2)
        
        XCTAssertEqual(KeychainManager.load(forKey: key1), value1)
        XCTAssertEqual(KeychainManager.load(forKey: key2), value2)
        
        // Delete one should not affect the other
        try KeychainManager.delete(forKey: key1)
        
        XCTAssertNil(KeychainManager.load(forKey: key1))
        XCTAssertEqual(KeychainManager.load(forKey: key2), value2)
    }
    
    // MARK: - Empty String Tests
    
    func testSaveEmptyString() throws {
        let key = "test_key"
        let value = ""
        
        try KeychainManager.save(value, forKey: key)
        
        let loadedValue = KeychainManager.load(forKey: key)
        XCTAssertEqual(loadedValue, value, "Empty string should be saved and loaded correctly")
    }
    
    // MARK: - Special Characters Tests
    
    func testSpecialCharacters() throws {
        let key = "test_key"
        let value = "sk-ant-api03-!@#$%^&*()_+-=[]{}|;':\",./<>?"
        
        try KeychainManager.save(value, forKey: key)
        
        let loadedValue = KeychainManager.load(forKey: key)
        XCTAssertEqual(loadedValue, value, "Special characters should be preserved")
    }
    
    // MARK: - Long String Tests
    
    func testLongString() throws {
        let key = "test_key"
        let value = String(repeating: "a", count: 10000) // 10KB string
        
        try KeychainManager.save(value, forKey: key)
        
        let loadedValue = KeychainManager.load(forKey: key)
        XCTAssertEqual(loadedValue?.count, 10000, "Long string should be preserved completely")
    }
}