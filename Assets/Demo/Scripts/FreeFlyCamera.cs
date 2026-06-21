using UnityEngine;

public class FreeFlyCamera : MonoBehaviour
{
    [Header("Movement")]
    public float moveSpeed = 20f;
    public float fastMoveMultiplier = 4f;
    public float acceleration = 10f;
    public float scrollSpeedSensitivity = 5f;
    public float minimumMoveSpeed = 1f;
    public float maximumMoveSpeed = 500f;

    [Header("Look")]
    public float mouseSensitivity = 2f;
    public float minimumPitch = -89f;
    public float maximumPitch = 89f;

    [Header("Cursor")]
    public bool lockCursorOnStart = true;

    private Vector3 currentVelocity;
    private float yaw;
    private float pitch;
    private bool cursorLocked;

    private void Start()
    {
        Vector3 eulerAngles = transform.eulerAngles;
        yaw = eulerAngles.y;
        pitch = NormalizeAngle(eulerAngles.x);

        SetCursorLocked(lockCursorOnStart);
    }

    private void Update()
    {
        UpdateCursorState();

        if (!cursorLocked)
        {
            return;
        }

        UpdateLook();
        UpdateMoveSpeed();
        UpdateMovement();
    }

    private void UpdateLook()
    {
        float mouseX = Input.GetAxisRaw("Mouse X") * mouseSensitivity;
        float mouseY = Input.GetAxisRaw("Mouse Y") * mouseSensitivity;

        yaw += mouseX;
        pitch -= mouseY;
        pitch = Mathf.Clamp(pitch, minimumPitch, maximumPitch);

        transform.rotation = Quaternion.Euler(pitch, yaw, 0f);
    }

    private void UpdateMoveSpeed()
    {
        float scroll = Input.mouseScrollDelta.y;

        if (Mathf.Abs(scroll) > 0.001f)
        {
            moveSpeed += scroll * scrollSpeedSensitivity;
            moveSpeed = Mathf.Clamp(moveSpeed, minimumMoveSpeed, maximumMoveSpeed);
        }
    }

    private void UpdateMovement()
    {
        float horizontal = Input.GetAxisRaw("Horizontal");
        float vertical = Input.GetAxisRaw("Vertical");

        float verticalMovement = 0f;

        if (Input.GetKey(KeyCode.E))
        {
            verticalMovement += 1f;
        }

        if (Input.GetKey(KeyCode.Q))
        {
            verticalMovement -= 1f;
        }

        Vector3 inputDirection = new Vector3(horizontal, verticalMovement, vertical);
        inputDirection = Vector3.ClampMagnitude(inputDirection, 1f);

        Vector3 worldDirection =
            transform.right * inputDirection.x +
            Vector3.up * inputDirection.y +
            transform.forward * inputDirection.z;

        float currentSpeed = moveSpeed;

        if (Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.RightShift))
        {
            currentSpeed *= fastMoveMultiplier;
        }

        Vector3 targetVelocity = worldDirection * currentSpeed;

        currentVelocity = Vector3.Lerp(
            currentVelocity,
            targetVelocity,
            1f - Mathf.Exp(-acceleration * Time.deltaTime)
        );

        transform.position += currentVelocity * Time.deltaTime;
    }

    private void UpdateCursorState()
    {
        if (Input.GetKeyDown(KeyCode.Escape))
        {
            SetCursorLocked(false);
        }

        if (!cursorLocked && Input.GetMouseButtonDown(0))
        {
            SetCursorLocked(true);
        }
    }

    private void SetCursorLocked(bool locked)
    {
        cursorLocked = locked;
        Cursor.lockState = locked ? CursorLockMode.Locked : CursorLockMode.None;
        Cursor.visible = !locked;
    }

    private float NormalizeAngle(float angle)
    {
        if (angle > 180f)
        {
            angle -= 360f;
        }

        return angle;
    }

    private void OnDisable()
    {
        Cursor.lockState = CursorLockMode.None;
        Cursor.visible = true;
    }
}