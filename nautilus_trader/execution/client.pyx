# -------------------------------------------------------------------------------------------------
#  Copyright (C) 2015-2021 Nautech Systems Pty Ltd. All rights reserved.
#  https://nautechsystems.io
#
#  Licensed under the GNU Lesser General Public License Version 3.0 (the "License");
#  You may not use this file except in compliance with the License.
#  You may obtain a copy of the License at https://www.gnu.org/licenses/lgpl-3.0.en.html
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
# -------------------------------------------------------------------------------------------------

from nautilus_trader.common.clock cimport Clock
from nautilus_trader.common.logging cimport Logger
from nautilus_trader.common.logging cimport LoggerAdapter
from nautilus_trader.common.uuid cimport UUIDFactory
from nautilus_trader.core.correctness cimport Condition
from nautilus_trader.model.c_enums.liquidity_side cimport LiquiditySide
from nautilus_trader.model.c_enums.order_side cimport OrderSide
from nautilus_trader.model.commands cimport CancelOrder
from nautilus_trader.model.commands cimport SubmitBracketOrder
from nautilus_trader.model.commands cimport SubmitOrder
from nautilus_trader.model.commands cimport UpdateOrder
from nautilus_trader.model.currency cimport Currency
from nautilus_trader.model.events cimport AccountState
from nautilus_trader.model.events cimport Event
from nautilus_trader.model.events cimport OrderAccepted
from nautilus_trader.model.events cimport OrderCancelRejected
from nautilus_trader.model.events cimport OrderCanceled
from nautilus_trader.model.events cimport OrderExpired
from nautilus_trader.model.events cimport OrderFilled
from nautilus_trader.model.events cimport OrderInvalid
from nautilus_trader.model.events cimport OrderPendingCancel
from nautilus_trader.model.events cimport OrderPendingReplace
from nautilus_trader.model.events cimport OrderRejected
from nautilus_trader.model.events cimport OrderSubmitted
from nautilus_trader.model.events cimport OrderTriggered
from nautilus_trader.model.events cimport OrderUpdateRejected
from nautilus_trader.model.events cimport OrderUpdated
from nautilus_trader.model.identifiers cimport AccountId
from nautilus_trader.model.identifiers cimport ClientId
from nautilus_trader.model.identifiers cimport ClientOrderId
from nautilus_trader.model.identifiers cimport ExecutionId
from nautilus_trader.model.identifiers cimport InstrumentId
from nautilus_trader.model.identifiers cimport PositionId
from nautilus_trader.model.identifiers cimport StrategyId
from nautilus_trader.model.identifiers cimport VenueOrderId
from nautilus_trader.model.objects cimport Money
from nautilus_trader.model.objects cimport Price
from nautilus_trader.model.objects cimport Quantity
from nautilus_trader.model.orders.base cimport Order


cdef class ExecutionClient:
    """
    The abstract base class for all execution clients.

    This class should not be used directly, but through its concrete subclasses.
    """

    def __init__(
        self,
        ClientId client_id not None,
        AccountId account_id not None,
        ExecutionEngine engine not None,
        Clock clock not None,
        Logger logger not None,
        dict config=None,
    ):
        """
        Initialize a new instance of the `ExecutionClient` class.

        Parameters
        ----------
        client_id : ClientId
            The client identifier.
        account_id : AccountId
            The account identifier for the client.
        engine : ExecutionEngine
            The execution engine to connect to the client.
        clock : Clock
            The clock for the component.
        logger : Logger
            The logger for the component.
        config : dict[str, object], optional
            The configuration options.

        Raises
        ------
        ValueError
            If client_id is not equal to account_id.issuer.

        """
        Condition.equal(client_id.value, account_id.issuer, "client_id.value", "account_id.issuer")

        if config is None:
            config = {}

        self._clock = clock
        self._uuid_factory = UUIDFactory()
        self._log = LoggerAdapter(
            component=config.get("name", f"ExecClient-{client_id.value}"),
            logger=logger,
        )
        self._engine = engine
        self._config = config

        self.id = client_id
        self.account_id = account_id
        self.is_connected = False

        self._log.info(f"Initialized.")

    def __repr__(self) -> str:
        return f"{type(self).__name__}-{self.id.value}"

    cpdef void _set_connected(self, bint value=True) except *:
        """
        Setter for pure Python implementations to change the readonly property.

        Parameters
        ----------
        value : bool
            The value to set for is_connected.

        """
        self.is_connected = value

    cpdef void connect(self) except *:
        """Abstract method (implement in subclass)."""
        raise NotImplementedError("method must be implemented in the subclass")

    cpdef void disconnect(self) except *:
        """Abstract method (implement in subclass)."""
        raise NotImplementedError("method must be implemented in the subclass")

    cpdef void reset(self) except *:
        """Abstract method (implement in subclass)."""
        raise NotImplementedError("method must be implemented in the subclass")

    cpdef void dispose(self) except *:
        """Abstract method (implement in subclass)."""
        raise NotImplementedError("method must be implemented in the subclass")

# -- COMMAND HANDLERS ------------------------------------------------------------------------------

    cpdef void submit_order(self, SubmitOrder command) except *:
        """Abstract method (implement in subclass)."""
        raise NotImplementedError("method must be implemented in the subclass")

    cpdef void submit_bracket_order(self, SubmitBracketOrder command) except *:
        """Abstract method (implement in subclass)."""
        raise NotImplementedError("method must be implemented in the subclass")

    cpdef void update_order(self, UpdateOrder command) except *:
        """Abstract method (implement in subclass)."""
        raise NotImplementedError("method must be implemented in the subclass")

    cpdef void cancel_order(self, CancelOrder command) except *:
        """Abstract method (implement in subclass)."""
        raise NotImplementedError("method must be implemented in the subclass")

# -- EVENT HANDLERS --------------------------------------------------------------------------------

    cpdef void generate_account_state(
        self,
        list balances,
        list balances_free,
        list balances_locked,
        dict info=None,
    ) except *:
        """
        Generate an `AccountState` event and send it to the `ExecutionEngine`.

        Parameters
        ----------
        balances : list[Money]
            The current account balances.
        balances_free : list[Money]
            The account balances free for trading.
        balances_locked : list[Money]
            The account balances locked (assigned as margin collateral).
        info : dict [str, object]
            The additional implementation specific account information.

        """
        if info is None:
            info = {}

        # Generate event
        cdef AccountState account_state = AccountState(
            account_id=self.account_id,
            balances=balances,
            balances_free=balances_free,
            balances_locked=balances_locked,
            info=info,
            event_id=self._uuid_factory.generate(),
            timestamp_ns=self._clock.timestamp_ns(),
        )

        self._handle_event(account_state)

    cpdef void generate_order_invalid(
        self,
        ClientOrderId client_order_id,
        str reason,
    ) except *:
        """
        Generate an `OrderInvalid` event and send it to the `ExecutionEngine`.

        Parameters
        ----------
        client_order_id : ClientOrderId
            The client order identifier.
        reason : str
            The order invalid reason.

        """
        # Generate event
        cdef OrderInvalid invalid = OrderInvalid(
            client_order_id=client_order_id,
            reason=reason,
            event_id=self._uuid_factory.generate(),
            timestamp_ns=self._clock.timestamp_ns(),
        )

        self._handle_event(invalid)

    cpdef void generate_order_submitted(
        self, ClientOrderId client_order_id,
        int64_t submitted_ns,
    ) except *:
        """
        Generate an `OrderSubmitted` event and send it to the `ExecutionEngine`.

        Parameters
        ----------
        client_order_id : ClientOrderId
            The client order identifier.
        submitted_ns : int64
            The Unix timestamp (nanos) when the order was submitted.

        """
        # Generate event
        cdef OrderSubmitted submitted = OrderSubmitted(
            self.account_id,
            client_order_id=client_order_id,
            submitted_ns=submitted_ns,
            event_id=self._uuid_factory.generate(),
            timestamp_ns=self._clock.timestamp_ns(),
        )

        self._handle_event(submitted)

    cpdef void generate_order_rejected(
        self,
        ClientOrderId client_order_id,
        str reason,
        int64_t rejected_ns,
    ) except *:
        """
        Generate an `OrderRejected` event and send it to the `ExecutionEngine`.

        Parameters
        ----------
        client_order_id : ClientOrderId
            The client order identifier.
        reason : datetime
            The order rejected reason.
        rejected_ns : int64
            The Unix timestamp (nanos) when the order was rejected.

        """
        # Generate event
        cdef OrderRejected rejected = OrderRejected(
            self.account_id,
            client_order_id=client_order_id,
            reason=reason,
            rejected_ns=rejected_ns,
            event_id=self._uuid_factory.generate(),
            timestamp_ns=self._clock.timestamp_ns(),
        )

        self._handle_event(rejected)

    cpdef void generate_order_accepted(
        self,
        ClientOrderId client_order_id,
        VenueOrderId venue_order_id,
        int64_t accepted_ns,
    ) except *:
        """
        Generate an `OrderAccepted` event and send it to the `ExecutionEngine`.

        Parameters
        ----------
        client_order_id : ClientOrderId
            The client order identifier.
        venue_order_id : VenueOrderId
            The venue order identifier.
        accepted_ns : int64
            The Unix timestamp (nanos) when the order was accepted.

        """
        # Generate event
        cdef OrderAccepted accepted = OrderAccepted(
            self.account_id,
            client_order_id=client_order_id,
            venue_order_id=venue_order_id,
            accepted_ns=accepted_ns,
            event_id=self._uuid_factory.generate(),
            timestamp_ns=self._clock.timestamp_ns(),
        )

        self._handle_event(accepted)

    cpdef void generate_order_pending_replace(
        self,
        ClientOrderId client_order_id,
        VenueOrderId venue_order_id,
        int64_t pending_ns,
    ) except *:
        """
        Generate an `OrderPendingReplace` event and send it to the `ExecutionEngine`.

        Parameters
        ----------
        client_order_id : ClientOrderId
            The client order identifier.
        venue_order_id : VenueOrderId
            The venue order identifier.
        pending_ns : datetime
            The Unix timestamp (nanos) when the replace was pending.

        """
        # Generate event
        cdef OrderPendingReplace pending_replace = OrderPendingReplace(
            account_id=self.account_id,
            client_order_id=client_order_id,
            venue_order_id=venue_order_id,
            pending_ns=pending_ns,
            event_id=self._uuid_factory.generate(),
            timestamp_ns=self._clock.timestamp_ns(),
        )

        self._handle_event(pending_replace)

    cpdef void generate_order_pending_cancel(
        self,
        ClientOrderId client_order_id,
        VenueOrderId venue_order_id,
        int64_t pending_ns,
    ) except *:
        """
        Generate an `OrderPendingCancel` event and send it to the `ExecutionEngine`.

        Parameters
        ----------
        client_order_id : ClientOrderId
            The client order identifier.
        venue_order_id : VenueOrderId
            The venue order identifier.
        pending_ns : datetime
            The Unix timestamp (nanos) when the cancel was pending.

        """
        # Generate event
        cdef OrderPendingCancel pending_cancel = OrderPendingCancel(
            account_id=self.account_id,
            client_order_id=client_order_id,
            venue_order_id=venue_order_id,
            pending_ns=pending_ns,
            event_id=self._uuid_factory.generate(),
            timestamp_ns=self._clock.timestamp_ns(),
        )

        self._handle_event(pending_cancel)

    cpdef void generate_order_update_rejected(
        self,
        ClientOrderId client_order_id,
        str response_to,
        str reason,
        int64_t rejected_ns,
    ) except *:
        """
        Generate an `OrderUpdateRejected` event and send it to the `ExecutionEngine`.

        Parameters
        ----------
        client_order_id : ClientOrderId
            The client order identifier.
        response_to : str
            The order update rejected response.
        reason : str
            The order update rejected reason.
        rejected_ns : datetime
            The Unix timestamp (nanos) when the order update was rejected.

        """
        cdef VenueOrderId venue_order_id = None
        cdef Order order = self._engine.cache.order(client_order_id)
        if order is not None:
            venue_order_id = order.venue_order_id
        else:
            venue_order_id = VenueOrderId.null_c()

        # Generate event
        cdef OrderUpdateRejected update_rejected = OrderUpdateRejected(
            account_id=self.account_id,
            client_order_id=client_order_id,
            venue_order_id=venue_order_id,
            response_to=response_to,
            reason=reason,
            rejected_ns=rejected_ns,
            event_id=self._uuid_factory.generate(),
            timestamp_ns=self._clock.timestamp_ns(),
        )

        self._handle_event(update_rejected)

    cpdef void generate_order_cancel_rejected(
        self,
        ClientOrderId client_order_id,
        str response_to,
        str reason,
        int64_t rejected_ns,
    ) except *:
        """
        Generate an `OrderCancelRejected` event and send it to the `ExecutionEngine`.

        Parameters
        ----------
        client_order_id : ClientOrderId
            The client order identifier.
        response_to : str
            The order cancel rejected response.
        reason : str
            The order cancel rejected reason.
        rejected_ns : datetime
            The Unix timestamp (nanos) when the order cancel was rejected.

        """
        cdef VenueOrderId venue_order_id = None
        cdef Order order = self._engine.cache.order(client_order_id)
        if order is not None:
            venue_order_id = order.venue_order_id
        else:
            venue_order_id = VenueOrderId.null_c()

        # Generate event
        cdef OrderCancelRejected cancel_rejected = OrderCancelRejected(
            account_id=self.account_id,
            client_order_id=client_order_id,
            venue_order_id=venue_order_id,
            response_to=response_to,
            reason=reason,
            rejected_ns=rejected_ns,
            event_id=self._uuid_factory.generate(),
            timestamp_ns=self._clock.timestamp_ns(),
        )

        self._handle_event(cancel_rejected)

    cpdef void generate_order_updated(
        self,
        ClientOrderId client_order_id,
        VenueOrderId venue_order_id,
        Quantity quantity,
        Price price,
        int64_t updated_ns,
        bint venue_order_id_modified=False,
    ) except *:
        """
        Generate an `OrderUpdated` event and send it to the `ExecutionEngine`.

        Parameters
        ----------
        client_order_id : ClientOrderId
            The client order identifier.
        venue_order_id : VenueOrderId
            The venue order identifier.
        quantity : Quantity
            The orders current quantity.
        price : Price
            The orders current price.
        updated_ns : int64
            The Unix timestamp (nanos) when the order was updated.
        venue_order_id_modified : bool
            If the identifier was modified for this event.

        """
        # Check venue_order_id against cache, only allow modification when `venue_order_id_modified=True`
        if not venue_order_id_modified:
            existing = self._engine.cache.venue_order_id(client_order_id)
            Condition.equal(existing, venue_order_id, "existing", "order.venue_order_id")

        # Generate event
        cdef OrderUpdated updated = OrderUpdated(
            account_id=self.account_id,
            client_order_id=client_order_id,
            venue_order_id=venue_order_id,
            quantity=quantity,
            price=price,
            updated_ns=updated_ns,
            event_id=self._uuid_factory.generate(),
            timestamp_ns=self._clock.timestamp_ns(),
        )

        self._handle_event(updated)

    cpdef void generate_order_canceled(
        self,
        ClientOrderId client_order_id,
        VenueOrderId venue_order_id,
        int64_t canceled_ns,
    ) except *:
        """
        Generate an `OrderCanceled` event and send it to the `ExecutionEngine`.

        Parameters
        ----------
        client_order_id : ClientOrderId
            The client order identifier.
        venue_order_id : VenueOrderId
            The venue order identifier.
        canceled_ns : int64
            The Unix timestamp (nanos) when order was canceled.

        """
        # Generate event
        cdef OrderCanceled canceled = OrderCanceled(
            account_id=self.account_id,
            client_order_id=client_order_id,
            venue_order_id=venue_order_id,
            canceled_ns=canceled_ns,
            event_id=self._uuid_factory.generate(),
            timestamp_ns=self._clock.timestamp_ns(),
        )

        self._handle_event(canceled)

    cpdef void generate_order_triggered(
        self,
        ClientOrderId client_order_id,
        VenueOrderId venue_order_id,
        int64_t triggered_ns,
    ) except *:
        """
        Generate an `OrderTriggered` event and send it to the `ExecutionEngine`.

        Parameters
        ----------
        client_order_id : ClientOrderId
            The client order identifier.
        venue_order_id : VenueOrderId
            The venue order identifier.
        triggered_ns : int64
            The Unix timestamp (nanos) when the order was triggered.

        """
        # Generate event
        cdef OrderTriggered triggered = OrderTriggered(
            account_id=self.account_id,
            client_order_id=client_order_id,
            venue_order_id=venue_order_id,
            triggered_ns=triggered_ns,
            event_id=self._uuid_factory.generate(),
            timestamp_ns=self._clock.timestamp_ns(),
        )

        self._handle_event(triggered)

    cpdef void generate_order_expired(
        self,
        ClientOrderId client_order_id,
        VenueOrderId venue_order_id,
        int64_t expired_ns,
    ) except *:
        """
        Generate an `OrderExpired` event and send it to the `ExecutionEngine`.

        Parameters
        ----------
        client_order_id : ClientOrderId
            The client order identifier.
        venue_order_id : VenueOrderId
            The venue order identifier.
        expired_ns : int64
            The Unix timestamp (nanos) when the order expired.

        """
        # Generate event
        cdef OrderExpired expired = OrderExpired(
            account_id=self.account_id,
            client_order_id=client_order_id,
            venue_order_id=venue_order_id,
            expired_ns=expired_ns,
            event_id=self._uuid_factory.generate(),
            timestamp_ns=self._clock.timestamp_ns(),
        )

        self._handle_event(expired)

    cpdef void generate_order_filled(
        self,
        ClientOrderId client_order_id,
        VenueOrderId venue_order_id,
        ExecutionId execution_id,
        PositionId position_id,  # Can be None
        InstrumentId instrument_id,
        OrderSide order_side,
        Quantity last_qty,
        Price last_px,
        Currency quote_currency,
        Money commission,
        LiquiditySide liquidity_side,
        int64_t execution_ns,
    ) except *:
        """
        Generate an `OrderFilled` event and send it to the `ExecutionEngine`.

        Parameters
        ----------
        client_order_id : ClientOrderId
            The client order identifier.
        venue_order_id : VenueOrderId
            The venue order identifier.
        execution_id : ExecutionId
            The execution identifier.
        position_id : PositionId
            The position identifier associated with the order.
        instrument_id : InstrumentId
            The instrument identifier.
        order_side : OrderSide
            The execution order side.
        last_qty : Quantity
            The fill quantity for this execution.
        last_px : Price
            The fill price for this execution (not average price).
        quote_currency : Currency
            The currency of the price.
        commission : Money
            The fill commission.
        liquidity_side : LiquiditySide
            The execution liquidity side.
        execution_ns : int64
            The Unix timestamp (nanos) when the order was filled.

        """
        # Generate event
        cdef OrderFilled fill = OrderFilled(
            account_id=self.account_id,
            client_order_id=client_order_id,
            venue_order_id=venue_order_id,
            execution_id=execution_id,
            position_id=position_id or PositionId.null_c(),  # If 'NULL' then assigned in engine
            strategy_id=StrategyId.null_c(),                 # If 'NULL' then assigned in engine
            instrument_id=instrument_id,
            order_side=order_side,
            last_qty=last_qty,
            last_px=last_px,
            currency=quote_currency,
            commission=commission,
            liquidity_side=liquidity_side,
            execution_ns=execution_ns,
            event_id=self._uuid_factory.generate(),
            timestamp_ns=self._clock.timestamp_ns(),
        )

        self._handle_event(fill)

# -- EVENT HANDLERS --------------------------------------------------------------------------------

    cdef void _handle_event(self, Event event) except *:
        self._engine.process(event)
